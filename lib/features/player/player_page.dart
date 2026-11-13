import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/native_bridge.dart';
import '../../core/settings_controller.dart';
import '../../data/models/video_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../shared/utils/format.dart';

/// Full-featured player screen.
///
/// Gestures (modelled after animeko's PlayerGestureHost / PiliPlus player):
///  * single tap     -> toggle controls
///  * double tap     -> play / pause
///  * swipe right/left -> seek (with live preview bubble)
///  * swipe up/down  -> brightness (left) / volume (right)
///  * long press     -> temporary 3x speed, release to restore
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.item, required this.source});

  final VideoItem item;
  final ResolvedSource source;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final VideoPlayerController _controller;
  late final LibraryRepository _library;

  bool _ready = false;
  String? _error;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  double _positionMs = 0;
  double _durationMs = 0;
  double _bufferedMs = 0;
  double _speed = 1.0;
  bool _locked = false;

  // gesture scratch state
  _DragMode? _dragMode;
  double _dragStartValue = 0; // brightness / volume at drag start
  double _dragDeltaFraction = 0;
  double _brightnessValue = 1.0;
  double _volumeValue = 1.0;
  bool _longPressActive = false;
  static const double _longPressSpeed = 3.0;

  @override
  void initState() {
    super.initState();
    _library = context.read<LibraryRepository>();
    _speed = context.read<SettingsController>().defaultSpeed;
    _init();
    WakelockPlus.enable();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(
      Uri.parse(widget.source.url),
      httpHeaders: widget.source.headers,
    );
    _controller = c;
    try {
      await c.initialize();
      await c.setPlaybackSpeed(_speed);
      final resume = _library.historyPosition(widget.item.viewKey);
      if (resume > 2000 && resume < c.value.duration.inMilliseconds - 3000) {
        await c.seekTo(Duration(milliseconds: resume));
      }
      c.addListener(_onTick);
      await c.play();
      if (mounted) setState(() => _ready = true);
      _scheduleHide();
    } catch (e) {
      if (mounted) setState(() => _error = '播放失败：$e');
    }
  }

  void _onTick() {
    if (!mounted) return;
    final v = _controller.value;
    setState(() {
      _positionMs = v.position.inMilliseconds.toDouble();
      _durationMs = v.duration.inMilliseconds.toDouble();
      _bufferedMs = v.buffered.isEmpty
          ? 0
          : v.buffered.last.end.inMilliseconds.toDouble();
    });
    // persist progress periodically
    if (v.position.inSeconds % 5 == 0 && v.isPlaying) {
      _library.recordHistory(widget.item, positionMs: v.position.inMilliseconds);
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && !_locked) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  Future<void> _enterFullscreen(bool full) async {
    setState(() => _controlsVisible = true);
    if (full) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _scheduleHide();
  }

  Future<void> _setSpeed(double s) async {
    setState(() => _speed = s);
    await _controller.setPlaybackSpeed(s);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    try {
      NativeBridge.resetBrightness();
    } catch (_) {}
    _controller.removeListener(_onTick);
    final pos = _controller.value.position.inMilliseconds;
    _library.recordHistory(widget.item, positionMs: pos);
    _controller.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: false,
        bottom: false,
        child: _error != null
            ? _ErrorView(message: _error!, onBack: () => Navigator.pop(context))
            : !_ready
                ? const Center(child: CircularProgressIndicator())
                : _buildPlayer(),
      ),
    );
  }

  Widget _buildPlayer() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      onDoubleTap: () {
        if (_controller.value.isPlaying) {
          _controller.pause();
        } else {
          _controller.play();
        }
        _scheduleHide();
      },
      onLongPressStart: (_) {
        _longPressActive = true;
        _controller.setPlaybackSpeed(_longPressSpeed);
        setState(() {});
      },
      onLongPressEnd: (_) {
        _longPressActive = false;
        _controller.setPlaybackSpeed(_speed);
        setState(() {});
      },
      onHorizontalDragStart: _locked
          ? null
          : (d) {
              _dragMode = _DragMode.seek;
              _dragDeltaFraction = 0;
              _scheduleHide();
            },
      onHorizontalDragUpdate: _locked
          ? null
          : (d) {
              final width = MediaQuery.of(context).size.width;
              _dragDeltaFraction += d.delta.dx / width;
              setState(() {});
            },
      onHorizontalDragEnd: _locked
          ? null
          : (d) {
              final target = ((_positionMs + _dragDeltaFraction * _durationMs)
                      .clamp(0.0, _durationMs) as num)
                  .toDouble();
              _controller.seekTo(Duration(milliseconds: target.toInt()));
              _dragMode = null;
              _dragDeltaFraction = 0;
              setState(() {});
            },
      onVerticalDragStart: _locked
          ? null
          : (d) {
              final size = MediaQuery.of(context).size;
              final left = d.localPosition.dx < size.width / 2;
              _dragMode = left ? _DragMode.brightness : _DragMode.volume;
              _dragStartValue = left ? _brightnessValue : _volumeValue;
              _scheduleHide();
            },
      onVerticalDragUpdate: _locked
          ? null
          : (d) {
              final size = MediaQuery.of(context).size;
              final frac = -d.delta.dy / size.height;
              final next = ((_dragStartValue + frac).clamp(0.0, 1.0) as num).toDouble();
              if (_dragMode == _DragMode.brightness) {
                _brightnessValue = next;
                NativeBridge.setBrightness(next);
              } else if (_dragMode == _DragMode.volume) {
                _volumeValue = next;
                _controller.setVolume(next);
              }
              _dragStartValue = next;
              setState(() {});
            },
      onVerticalDragEnd: (_) {
        _dragMode = null;
        setState(() {});
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio == 0
                  ? 16 / 9
                  : _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
          if (_dragMode == _DragMode.seek && _dragDeltaFraction != 0)
            _seekBubble(),
          if (_dragMode == _DragMode.brightness) _osdBubble(Icons.brightness_6, _brightnessValue),
          if (_dragMode == _DragMode.volume) _osdBubble(Icons.volume_up, _volumeValue),
          if (_longPressActive)
            const Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: Center(child: _Pill(text: '3x 快进中')),
            ),
          if (!_controller.value.isPlaying && !_controlsVisible)
            Center(
              child: IconButton.filled(
                iconSize: 56,
                onPressed: () {
                  _controller.play();
                  _scheduleHide();
                },
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ),
          AnimatedOpacity(
            opacity: _controlsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: _controlsLayer(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seekBubble() {
    final target =
        ((_positionMs + _dragDeltaFraction * _durationMs).clamp(0.0, _durationMs) as num)
            .toDouble();
    return Center(
      child: _Pill(
        text: '${Format.duration(target ~/ 1000)} / ${Format.duration(_durationMs ~/ 1000)}',
      ),
    );
  }

  Widget _osdBubble(IconData icon, double value) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 10),
            SizedBox(
              width: 90,
              child: LinearProgressIndicator(value: value, minHeight: 6),
            ),
            const SizedBox(width: 8),
            Text('${(value * 100).round()}%', style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _controlsLayer() {
    final playing = _controller.value.isPlaying;
    return Stack(
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withOpacity(0.6), Colors.transparent],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ),
                  IconButton(
                    icon: Icon(_locked ? Icons.lock : Icons.lock_open,
                        color: Colors.white),
                    tooltip: '锁定',
                    onPressed: () => setState(() => _locked = !_locked),
                  ),
                ],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.75), Colors.transparent],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(Format.duration(_positionMs ~/ 1000),
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                      Expanded(
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: LinearProgressIndicator(
                                value: _durationMs > 0 ? _bufferedMs / _durationMs : 0.0,
                                minHeight: 3,
                                backgroundColor: Colors.white24,
                                valueColor:
                                    const AlwaysStoppedAnimation(Colors.white38),
                              ),
                            ),
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape:
                                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: SliderComponentShape.noOverlay,
                              ),
                              child: Slider(
                                min: 0.0,
                                max: _durationMs > 0 ? _durationMs : 1.0,
                                value: (_positionMs.clamp(0.0, _durationMs > 0 ? _durationMs : 1.0) as num).toDouble(),
                                onChanged: (v) => setState(() => _positionMs = v),
                                onChangeEnd: (v) =>
                                    _controller.seekTo(Duration(milliseconds: v.toInt())),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(Format.duration(_durationMs ~/ 1000),
                          style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(playing ? Icons.pause : Icons.play_arrow,
                            color: Colors.white),
                        onPressed: () {
                          if (playing) {
                            _controller.pause();
                          } else {
                            _controller.play();
                          }
                          _scheduleHide();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.speed, color: Colors.white),
                        tooltip: '倍速',
                        onPressed: _showSpeedSheet,
                      ),
                      IconButton(
                        icon: const Icon(Icons.high_quality_outlined, color: Colors.white),
                        tooltip: '画质',
                        onPressed: _showQualitySheet,
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _showSpeedSheet,
                        child: Text('${_speed}x',
                            style: const TextStyle(color: Colors.white)),
                      ),
                      IconButton(
                        icon: const Icon(Icons.fullscreen, color: Colors.white),
                        tooltip: '全屏',
                        onPressed: () => _enterFullscreen(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showSpeedSheet() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 2.5];
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('播放速度', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Wrap(
              spacing: 8,
              children: speeds
                  .map((s) => ChoiceChip(
                        label: Text('${s}x'),
                        selected: _speed == s,
                        onSelected: (_) {
                          _setSpeed(s);
                          Navigator.pop(ctx);
                        },
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ).whenComplete(_scheduleHide);
  }

  void _showQualitySheet() {
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('画质 / 源', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.check),
              title: Text(widget.source.name),
              subtitle: widget.source.videoId == null
                  ? null
                  : Text('id: ${widget.source.videoId}'),
              onTap: () => Navigator.pop(ctx),
            ),
            if (widget.source.isPlayable)
              const ListTile(
                leading: Icon(Icons.link),
                title: Text('直链（跟随 Referer/UA）'),
                subtitle: Text('单码率原画'),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ).whenComplete(_scheduleHide);
  }
}

enum _DragMode { seek, brightness, volume }

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.72),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 15)),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onBack});
  final String message;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(message, style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onBack, child: const Text('返回')),
          ],
        ),
      ),
    );
  }
}
