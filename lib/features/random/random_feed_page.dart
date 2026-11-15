import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../data/models/video_item.dart';
import '../../data/repositories/video_repository.dart';

/// A full-screen "random" feed: on entry it plays a random video, and swiping
/// up/down plays another random one. The random pool is the 「评论最多」(md)
/// category, so picked videos have many comments.
class RandomFeedPage extends StatefulWidget {
  const RandomFeedPage({super.key, this.isActive = true});

  /// Whether this tab is currently visible (pause playback when switched away).
  final bool isActive;

  @override
  State<RandomFeedPage> createState() => _RandomFeedPageState();
}

class _RandomFeedPageState extends State<RandomFeedPage> {
  final PageController _pc = PageController();
  final Random _rnd = Random();
  final List<VideoItem> _items = <VideoItem>[];
  final Set<String> _seen = <String>{};

  int _index = 0;
  bool _bootstrapping = true;
  bool _loadingMore = false;
  String? _error;

  /// Earliest archive date (91 launched 2015-09-02).
  static final DateTime _archiveStart = DateTime(2015, 9, 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  /// TRUE random across the whole archive: pick a RANDOM DATE between the site
  /// launch (2015-09-02) and today, pull that day's videos (date search covers
  /// all years, old ones included), and pick a random one. Empty days are
  /// retried so we keep sampling until we hit a day that has videos.
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
    setState(() {
      _items.add(first);
      _bootstrapping = false;
    });
    _loadMore();
  }

  Future<void> _loadMore({int count = 3}) async {
    if (_loadingMore) return;
    _loadingMore = true;
    try {
      for (var i = 0; i < count; i++) {
        final it = await _pick();
        if (it != null && mounted) {
          setState(() => _items.add(it));
        }
      }
    } finally {
      _loadingMore = false;
    }
  }

  void _onPageChanged(int i) {
    setState(() => _index = i);
    if (i >= _items.length - 2) _loadMore();
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
            resolve: (vk) => repo.resolve(vk),
            onNext: () => _pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeInOut),
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
    required this.onNext,
  });

  final VideoItem item;
  final bool active;
  final Future<ResolvedSource> Function(String viewKey) resolve;
  final VoidCallback onNext;

  @override
  State<_RandomVideoSlide> createState() => _RandomVideoSlideState();
}

class _RandomVideoSlideState extends State<_RandomVideoSlide> {
  VideoPlayerController? _c;
  bool _requested = false;
  bool _ready = false;
  String? _err;

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

  Future<void> _ensureLoaded() async {
    if (_requested) return;
    _requested = true;
    try {
      final src = await widget.resolve(widget.item.viewKey);
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

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Cover as background placeholder.
          if (widget.item.cover.isNotEmpty)
            Image.network(widget.item.cover, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black)),
          if (_ready && _c != null)
            Center(
              child: AspectRatio(
                aspectRatio: _c!.value.aspectRatio == 0 ? 9 / 16 : _c!.value.aspectRatio,
                child: VideoPlayer(_c!),
              ),
            )
          else
            const Center(child: CircularProgressIndicator()),
          if (_err != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('播放失败：$_err',
                    style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
              ),
            ),
          // Bottom gradient + title.
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 20),
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
                  Text(
                    widget.item.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text('上滑 / 下滑 换一个随机视频 · 点击暂停',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
