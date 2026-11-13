import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/native_bridge.dart';
import '../../data/models/video_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/video_repository.dart';
import '../download/download_service.dart';
import '../player/player_page.dart';

/// Convenience entry used everywhere a card is tapped.
void openDetail(BuildContext context, VideoItem item) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => DetailPage(initial: item)),
  );
}

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.initial});
  final VideoItem initial;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late VideoItem _item = widget.initial;
  bool _loading = true;
  bool _fav = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _fav = context.read<LibraryRepository>().isFavorite(widget.initial.viewKey);
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await context.read<VideoRepository>().detail(widget.initial.viewKey);
      if (mounted) {
        setState(() {
          _item = _item.copyWith(
            title: detail.title.isNotEmpty ? detail.title : null,
            cover: detail.cover.isNotEmpty ? detail.cover : null,
            ownerName: detail.ownerName.isNotEmpty ? detail.ownerName : null,
            info: detail.info.isNotEmpty ? detail.info : null,
          );
        });
      }
    } catch (_) {
      // keep initial card data
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _play() async {
    setState(() => _busy = true);
    _toast('正在解析播放地址…');
    final repo = context.read<VideoRepository>();
    try {
      final src = await repo.resolve(_item.viewKey);
      if (!mounted) return;
      context.read<LibraryRepository>().recordHistory(_item);
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerPage(item: _item, source: src),
        ),
      );
    } catch (e) {
      final log = repo.api.lastAttemptLog;
      _toast(log.isEmpty ? '$e' : '$e\n\n尝试记录：\n$log');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    setState(() => _busy = true);
    _toast('正在解析下载地址…');
    try {
      final src = await context.read<VideoRepository>().resolve(_item.viewKey);
      await context.read<DownloadService>().start(_item, src);
      _toast('已加入下载');
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFav() async {
    final now = await context.read<LibraryRepository>().toggleFavorite(_item);
    if (mounted) setState(() => _fav = now);
    _toast(now ? '已收藏' : '已取消收藏');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '分享',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => NativeBridge.share(
              '${_item.title}\n${_item.pageUrl}\n§ stream: ${_item.viewKey}',
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_item.cover.isNotEmpty)
                  Image.network(_item.cover, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: Colors.black12))
                else
                  Container(color: Colors.black12),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
                    ),
                  ),
                ),
                Center(
                  child: _busy
                      ? const CircularProgressIndicator()
                      : IconButton.filled(
                          iconSize: 42,
                          onPressed: _play,
                          icon: const Icon(Icons.play_arrow_rounded),
                        ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_item.title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                const SizedBox(height: 8),
                if (_item.ownerName.isNotEmpty)
                  Text('UP：${_item.ownerName}', style: TextStyle(color: scheme.onSurface.withOpacity(0.6))),
                if (_item.info.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_item.info,
                        style: TextStyle(color: scheme.onSurface.withOpacity(0.5), fontSize: 12)),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _play,
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('播放'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: '下载',
                  onPressed: _busy ? null : _download,
                  icon: const Icon(Icons.download_outlined),
                ),
                const SizedBox(width: 6),
                IconButton.outlined(
                  tooltip: _fav ? '取消收藏' : '收藏',
                  onPressed: _toggleFav,
                  icon: Icon(_fav ? Icons.favorite : Icons.favorite_border,
                      color: _fav ? Colors.redAccent : null),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('来源：91porn · viewkey=${_item.viewKey}',
                style: TextStyle(color: scheme.onSurface.withOpacity(0.35), fontSize: 12)),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}
