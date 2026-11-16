import 'package:flutter/material.dart';

import '../../data/models/video_item.dart';
import 'status_view.dart';
import 'video_card.dart';
import 'video_grid.dart'; // videoGridDelegate

/// Explicit page-number browser for a 91 listing.
///
/// IMPORTANT: app-page N == server-page N (strict 1:1). We do NOT remap pages
/// via any "block" math — that made "第19页" point at a deeper server page when
/// the videos-per-page setting was changed, so forward paging looked 错乱.
///
/// De-duplication is applied per page (91 repeats cards / re-publishes the same
/// video under several viewKeys with the same cover). "Next" keeps going while
/// the last page returned items; it does NOT rely on a (possibly wrong) total.
class PagedVideoBrowser extends StatefulWidget {
  const PagedVideoBrowser({
    super.key,
    required this.fetch,
    required this.pageSize,
    required this.onItemTap,
    this.emptyText = '暂无内容',
  });

  final Future<PagedResult> Function(int serverPage) fetch;

  /// Kept for API compatibility; the list now shows exactly one server page.
  final int pageSize;
  final void Function(VideoItem item) onItemTap;
  final String emptyText;

  @override
  State<PagedVideoBrowser> createState() => _PagedVideoBrowserState();
}

class _PagedVideoBrowserState extends State<PagedVideoBrowser> {
  final ScrollController _scroll = ScrollController();

  int _appPage = 1;
  List<VideoItem> _items = <VideoItem>[];
  bool _loading = true;
  String? _error;
  bool _lastHadItems = true;

  @override
  void initState() {
    super.initState();
    _load(1);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _canNext => _lastHadItems;

  Future<void> _load(int appPage) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.fetch(appPage);
      _items = _dedupe(r.items);
      _lastHadItems = r.items.isNotEmpty;
      _appPage = appPage;
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scrollTop();
      }
    }
  }

  void _scrollTop() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  List<VideoItem> _dedupe(List<VideoItem> items) {
    final seenVk = <String>{};
    final seenThumb = <String>{};
    final out = <VideoItem>[];
    for (final it in items) {
      final t = it.thumbId;
      if (it.viewKey.isNotEmpty && seenVk.contains(it.viewKey)) continue;
      if (t != null && seenThumb.contains(t)) continue;
      if (it.viewKey.isNotEmpty) seenVk.add(it.viewKey);
      if (t != null) seenThumb.add(t);
      out.add(it);
    }
    return out;
  }

  Future<void> _promptJump() async {
    final controller = TextEditingController(text: '$_appPage');
    const maxPage = 100000;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳到第几页'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '起始页'),
          onSubmitted: (v) => Navigator.pop(ctx, int.tryParse(v.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text.trim())),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (result != null) {
      final p = result.clamp(1, maxPage).toInt();
      if (p != _appPage) _load(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const StatusView(loading: true);
    if (_error != null) return StatusView(error: _error, onRetry: () => _load(_appPage));
    if (_items.isEmpty && _appPage == 1) {
      return StatusView(empty: true, emptyText: widget.emptyText);
    }

    return Column(
      children: [
        Expanded(
          child: _items.isEmpty
              ? const StatusView(empty: true, emptyText: '没有更多内容了，可返回上一页')
              : GridView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  gridDelegate: videoGridDelegate,
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    return VideoCard(item: item, onTap: () => widget.onItemTap(item));
                  },
                ),
        ),
        _buildPager(context),
      ],
    );
  }

  Widget _buildPager(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant.withOpacity(0.4))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '上一页',
              onPressed: _appPage > 1 ? () => _load(_appPage - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('第 $_appPage 页 · 本页 ${_items.length} 个',
                style: const TextStyle(fontSize: 13)),
            IconButton(
              tooltip: '下一页',
              onPressed: _canNext ? () => _load(_appPage + 1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(onPressed: _promptJump, child: const Text('跳转')),
          ],
        ),
      ),
    );
  }
}
