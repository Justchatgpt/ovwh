import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../../core/storage.dart';
import '../../data/models/download_task.dart';
import '../../data/models/video_item.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/video_repository.dart';
import '../../shared/utils/format.dart';
import '../../shared/widgets/status_view.dart';
import '../../shared/widgets/video_grid.dart';
import '../detail/detail_page.dart';
import '../download/download_service.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('媒体库'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '收藏'),
              Tab(text: '历史'),
              Tab(text: '下载'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '清空历史',
              icon: const Icon(Icons.history_toggle_off),
              onPressed: () async {
                await context.read<LibraryRepository>().clearHistory();
              },
            ),
          ],
        ),
        body: const TabBarView(
          children: [_FavoritesTab(), _HistoryTab(), _DownloadsTab()],
        ),
      ),
    );
  }
}

class _FavoritesTab extends StatelessWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryRepository>();
    return ValueListenableBuilder(
      valueListenable: LocalStore.favorites.listenable(),
      builder: (context, _, __) {
        final items = library.getFavorites();
        if (items.isEmpty) {
          return const StatusView(empty: true, emptyText: '还没有收藏，长按视频卡片可收藏');
        }
        return CustomScrollView(
          slivers: [
            videoGridSliver(
              items,
              onTap: (item) => openDetail(context, item),
              onLongPress: (item) => _confirmRemove(context, library, item),
            ),
          ],
        );
      },
    );
  }

  void _confirmRemove(BuildContext context, LibraryRepository library, VideoItem item) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('取消收藏'),
        content: Text(item.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              library.removeFavorite(item.viewKey);
              Navigator.pop(ctx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context) {
    final library = context.read<LibraryRepository>();
    return ValueListenableBuilder(
      valueListenable: LocalStore.history.listenable(),
      builder: (context, _, __) {
        final items = library.getHistory();
        if (items.isEmpty) {
          return const StatusView(empty: true, emptyText: '暂无观看记录');
        }
        return CustomScrollView(
          slivers: [
            videoGridSliver(items, onTap: (item) => openDetail(context, item)),
          ],
        );
      },
    );
  }
}

class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab();

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadService>();
    final tasks = downloads.tasks;
    if (tasks.isEmpty) {
      return const StatusView(empty: true, emptyText: '暂无下载任务');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _DownloadTile(task: tasks[i]),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({required this.task});
  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final downloads = context.read<DownloadService>();
    final videoRepo = context.read<VideoRepository>();
    final scheme = Theme.of(context).colorScheme;
    final done = task.status == DownloadStatus.completed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 96,
                height: 56,
                child: task.cover.isEmpty
                    ? Container(color: Colors.black12, child: const Icon(Icons.movie))
                    : Image.network(task.cover, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(color: Colors.black12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: done ? 1 : task.progress,
                    minHeight: 4,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    done
                        ? '已完成 · ${Format.bytes(task.totalBytes)}'
                        : '${(task.progress * 100).toStringAsFixed(0)}% · ${Format.speed(task.speed)}',
                    style: TextStyle(fontSize: 11, color: scheme.onSurface.withOpacity(0.6)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (!done)
              IconButton(
                tooltip: task.status == DownloadStatus.downloading ? '暂停' : '继续',
                icon: Icon(task.status == DownloadStatus.downloading
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline),
                onPressed: () async {
                  if (task.status == DownloadStatus.downloading) {
                    downloads.pause(task.viewKey);
                  } else {
                    final item = VideoItem(viewKey: task.viewKey, title: task.title, cover: task.cover);
                    try {
                      final src = await videoRepo.resolve(task.viewKey);
                      await downloads.resume(item, src);
                    } catch (_) {}
                  }
                },
              ),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => downloads.remove(task.viewKey),
            ),
          ],
        ),
      ),
    );
  }
}
