import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../data/models/video_item.dart';
import '../../data/repositories/video_repository.dart';

/// Full-screen "random" feed: plays a random video on entry; swiping up/down
/// plays another. TRUE random across the whole archive.
///
/// Performance: we DON'T fetch one video at a time. A single date-search returns
/// ~24 videos for a random day; we pour all of them into a candidate pool and
/// serve from it, refilling in the background. Direct URLs of the next few are
/// prefetched. So most swipes need ZERO network.
class RandomFeedPage extends StatefulWidget {
  const RandomFeedPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  State<RandomFeedPage> createState() => _RandomFeedPageState();
}

class _RandomFeedPageState extends State<RandomFeedPage> {
  final PageController _pc = PageController();
  final Random _rnd = Random();
  final List<VideoItem> _items = <VideoItem>[];
  final List<VideoItem> _pool = <VideoItem>[];
  final Set<String> _seen = <String>{};
  final Map<String, Future<ResolvedSource>> _srcFutures = <String, Future<ResolvedSource>>{};

  int _index = 0;
  int _target = 0;
  bool _bootstrapping = true;
  bool _loading = false;
  bool _refilling = false;
  String? _error;

  static final DateTime _archiveStart = DateTime(2015, 9, 2);
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Don't preload/prefetch until this tab is actually opened.
    if (widget.isActive) _scheduleBootstrap();
  }

  @override
  void didUpdateWidget(covariant RandomFeedPage old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !_started) _scheduleBootstrap();
  }

  void _scheduleBootstrap() {
    if (_started) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  /// Fetch up to [batches] random days; each date-search yields ~24 videos that
  /// go into the pool. Skips empty days. One request typically fills 24 slots.
  Future<void> _fillPool({int batches = 2}) async {
    if (_refilling) return;
    _refilling = true;
    try {
      final repo = context.read<VideoRepository>();
      final today = DateTime.now();
      final span = today.difference(_archiveStart).inDays;
      if (span <= 0) return;
      var added = 0;
      for (var b = 0; b < batches && added < 60; b++) {
        for (var attempt = 0; attempt < 6; attempt++) {
          final d = _archiveStart.add(Duration(days: _rnd.nextInt(span + 1)));
          try {
            final pr = await repo.searchByDate(d, 1);
            final fresh = pr.items.where((it) => !_seen.contains(it.contentKey)).toList();
            if (fresh.isEmpty) continue; // empty day -> try another date
            for (final it in fresh) {
              _seen.add(it.contentKey);
              _pool.add(it);
            }
            added += fresh.length;
            break;
          } catch (_) {
            // network hiccup -> try another date
          }
        }
      }
      _pool.shuffle(_rnd);
      _prefetchAhead();
    } finally {
      _refilling = false;
    }
  }

  Future<VideoItem?> _takeFromPool() async {
    if (_pool.isEmpty) await _fillPool(batches: 2);
    if (_pool.isEmpty) return null;
    final it = _pool.removeAt(0);
    _prefetch(it);
    return it;
  }

  void _prefetch(VideoItem it) {
    if (!mounted) return;
    if (_srcFutures.containsKey(it.viewKey)) return;
    final repo = context.read<VideoRepository>();
    _srcFutures[it.viewKey] = repo.resolve(it.viewKey);
  }

  /// Warm up the direct URLs the user is likely to play next.
  void _prefetchAhead() {
    for (var k = _index; k <= _index + 2 && k < _items.length; k++) {
      _prefetch(_items[k]);
    }
    for (var k = 0; k < 3 && k < _pool.length; k++) {
      _prefetch(_pool[k]);
    }
  }

  Future<void> _bootstrap() async {
    _started = true;
    setState(() {
      _bootstrapping = true;
      _error = null;
    });
    final first = await _takeFromPool();
    if (!mounted) return;
    if (first == null) {
      setState(() {
        _bootstrapping = false;
        _error = '暂时取不到视频，点重试';
      });
      return;
    }
    setState(() {
      _items.add(first);
      _bootstrapping = false;
    });
    _prefetchAhead();
    _loadUntil(3);
    // Keep the pool topped up in the background so later swipes are instant.
    _fillPool(batches: 2);
  }

  Future<void> _loadUntil(int target) async {
    if (target > _target) _target = target;
    if (_loading) return;
    _loading = true;
    try {
      while (_items.length < _target) {
        final it = await _takeFromPool();
        if (it == null) break;
        if (!mounted) break;
        setState(() => _items.add(it));
        if (_pool.length < 8 && !_refilling) _fillPool(batches: 2);
      }
    } finally {
      _loading = false;
    }
    if (mounted) _prefetchAhead();
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    _prefetchAhead();
    if (i >= _items.length - 1) _loadUntil(i + 4);
    if (_pool.length < 8 && !_refilling) _fillPool(batches: 2);
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
        itemBuilder: (context, i) {
          if (i < _items.length) {
            final item = _items[i];
            return _RandomVideoSlide(
              item: item,
              active: widget.isActive && i == _index,
              source: _srcFutures[item.viewKey],
              resolve: (vk) => repo.resolve(vk),
            );
          }
          _loadUntil(i + 1);
          return _LoadingSlide(onRetry: () => _loadUntil(i + 1));
        },
      ),
    );
  }
}

class _LoadingSlide extends StatelessWidget {
  const _LoadingSlide({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            const Text('正在随机加载下一个…', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('没反应？点我重试')),
          ],
        ),
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
      ResolvedSource src;
      try {
        src = await (widget.source ?? widget.resolve(widget.item.viewKey));
      } catch (_) {
        // Prefetched future may have failed transiently -> resolve fresh once.
        src = await widget.resolve(widget.item.viewKey);
      }
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

  void _onTap() {
    if (_err != null) {
      _requested = false;
      setState(() => _err = null);
      _ensureLoaded();
      return;
    }
    _toggle();
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
      onTap: _onTap,
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
