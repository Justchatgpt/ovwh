import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../data/models/video_item.dart';
import '../../data/repositories/video_repository.dart';

/// Full-screen "random" feed: plays a random video on entry; swiping up/down
/// plays another. TRUE random across the whole archive — a random DATE between
/// the site launch (2015-09-02) and today, then a random video from that day.
class RandomFeedPage extends StatefulWidget {
  const RandomFeedPage({super.key, this.isActive = true});

  /// Whether this tab is visible (pause when switched away).
  final bool isActive;

  @override
  State<RandomFeedPage> createState() => _RandomFeedPageState();
}

class _RandomFeedPageState extends State<RandomFeedPage> {
  final PageController _pc = PageController();
  final Random _rnd = Random();
  final List<VideoItem> _items = <VideoItem>[];
  final Set<String> _seen = <String>{};
  final Map<String, Future<ResolvedSource>> _srcFutures = <String, Future<ResolvedSource>>{};

  int _index = 0;
  bool _bootstrapping = true;
  bool _loadingMore = false;
  String? _error;

  static final DateTime _archiveStart = DateTime(2015, 9, 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<VideoItem?> _pick() async {
    final repo = context.read<VideoRepository>();
    final today = DateTime.now();
    final spanDays = today.difference(_archiveStart).inDays;
    if (spanDays <= 0) return null;
    for (var t = 0; t < 18; t++) {
      final d = _archiveStart.add(Duration(days: _rnd.nextInt(spanDays + 1)));
      try {
        final pr = await repo.searchByDate(d, 1);
        if (pr.items.isEmpty) continue;
        final cand = pr.items.where((it) => !_seen.contains(it.contentKey)).toList();
        if (cand.isEmpty) continue;
        final it = cand[_rnd.nextInt(cand.length)];
        _seen.add(it.contentKey);
        return it;
      } catch (_) {
        // try another random date
      }
    }
    return null;
  }

  /// Resolve the direct URL in the background so playback starts fast.
  void _prefetch(VideoItem it) {
    if (_srcFutures.containsKey(it.viewKey)) return;
    final repo = context.read<VideoRepository>();
    _srcFutures[it.viewKey] = repo.resolve(it.viewKey);
  }

  Future<void> _bootstrap() async {
    setState(() {
      _bootstrapping = true;
      _error = null;
    });
    final first = await _pick();
    if (!mounted) return;
    if (first == null) {
      setState(() {
        _bootstrapping = false;
        _error = '暂时取不到视频，点重试';
      });
      return;
    }
    _prefetch(first);
    setState(() {
      _items.add(first);
      _bootstrapping = false;
    });
    _loadMore();
  }

  Future<void> _loadMore({int count = 2}) async {
    if (_loadingMore) return;
    _loadingMore = true;
    try {
      for (var i = 0; i < count; i++) {
        final it = await _pick();
        if (it != null && mounted) {
          _prefetch(it);
          setState(() => _items.add(it));
        }
      }
    } finally {
      _loadingMore = false;
    }
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    if (i >= _items.length - 2) _loadMore(count: 3);
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _items.isEmpty) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, color: Colors.white54, size: 40),
              const SizedBox(height: 8),
              Text(_error ?? '暂无内容', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _bootstrap, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    final repo = context.read<VideoRepository>();
    return ColoredBox(
      color: Colors.black,
      child: PageView.builder(
        controller: _pc,
        scrollDirection: Axis.vertical,
        onPageChanged: _onPageChanged,
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final item = _items[i];
          return _RandomVideoSlide(
            item: item,
            active: widget.isActive && i == _index,
            source: _srcFutures[item.viewKey],
            resolve: (vk) => repo.resolve(vk),
          );
        },
      ),
    );
  }
}

class _RandomVideoSlide extends StatefulWidget {
  const _RandomVideoSlide({
    required this.item,
    required this.active,
    required this.resolve,
    this.source,
  });

  final VideoItem item;
  final bool active;
  final Future<ResolvedSource> Function(String viewKey) resolve;
  final Future<ResolvedSource>? source;

  @override
  State<_RandomVideoSlide> createState() => _RandomVideoSlideState();
}

class _RandomVideoSlideState extends State<_RandomVideoSlide> {
  VideoPlayerController? _c;
  bool _requested = false;
  bool _ready = false;
  String? _err;
  int _lastTickMs = 0;

  @override
  void initState() {
    super.initState();
    if (widget.active) _ensureLoaded();
  }

  @override
  void didUpdateWidget(covariant _RandomVideoSlide old) {
    super.didUpdateWidget(old);
    if (widget.active) {
      _ensureLoaded();
      _c?.play();
    } else {
      _c?.pause();
    }
  }

  void _onTick() {
    if (!mounted) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastTickMs < 300) return;
    _lastTickMs = now;
    setState(() {});
  }

  Future<void> _ensureLoaded() async {
    if (_requested) return;
    _requested = true;
    try {
      final src = await (widget.source ?? widget.resolve(widget.item.viewKey));
      final c = VideoPlayerController.networkUrl(
        Uri.parse(src.url),
        httpHeaders: src.headers,
      );
      await c.initialize();
      await c.setLooping(true);
      if (!mounted) {
        await c.dispose();
        return;
      }
      _c = c;
      c.addListener(_onTick);
      setState(() => _ready = true);
      if (widget.active) c.play();
    } catch (e) {
      if (mounted) setState(() => _err = '$e');
    }
  }

  void _toggle() {
    final c = _c;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _c?.removeListener(_onTick);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _ready && _c != null;
    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.item.cover.isNotEmpty)
            Image.network(widget.item.cover, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black)),
          if (ready)
            Center(
              child: AspectRatio(
                aspectRatio: _c!.value.aspectRatio == 0 ? 9 / 16 : _c!.value.aspectRatio,
                child: VideoPlayer(_c!),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          if (ready && !_c!.value.isPlaying)
            const Center(child: Icon(Icons.play_arrow_rounded, size: 72, color: Colors.white70)),
          if (_err != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('播放失败：$_err',
                    style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
              ),
            ),
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 30, 8, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ready) ...[
                    Row(
                      children: [
                        IconButton(
                          onPressed: _toggle,
                          icon: Icon(_c!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white),
                        ),
                        Expanded(
                          child: VideoProgressIndicator(
                            _c!,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            colors: VideoProgressColors(
                              playedColor: Colors.white,
                              bufferedColor: Colors.white30,
                              backgroundColor: Colors.white12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                      child: Text('${_fmt(_c!.value.position)} / ${_fmt(_c!.value.duration)}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      widget.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 6),
                    child: Text('上滑 / 下滑 换一个随机视频 · 点击暂停',
                        style: TextStyle(color: Colors.white60, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
