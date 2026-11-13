import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/video_item.dart';
import 'status_view.dart';
import 'video_card.dart';
import 'video_grid.dart'; // videoGridDelegate

/// Explicit page-number browser for a 91 listing.
///
/// Key correctness points (learned from live data, 2026-11-14):
///  * The site renders each card several times → we de-dupe by `contentKey`
///    (real video id from the thumbnail, NOT viewKey, because one video is
///    published under multiple viewKeys with the same cover).
///  * De-duplicated server pages have *variable* item counts (18~24), so we do
///    NOT index into a global flat stream. Instead each app-page covers a
///    contiguous block of `k` server pages, where
///    `k = ceil(pageSize / serverPageSize)`. Consecutive blocks tile all server
///    pages exactly once → no item skipped, no item shown twice on a page, and
///    jumping to page P still costs only `k` fetches.
class PagedVideoBrowser extends StatefulWidget {
  const PagedVideoBrowser({
    super.key,
    required this.fetch,
    required this.pageSize,
    required this.onItemTap,
    this.emptyText = '暂无内容',
  });

  /// Fetch one *server* page (1-based).
  final Future<PagedResult> Function(int serverPage) fetch;
  final int pageSize;
  final void Function(VideoItem item) onItemTap;
  final String emptyText;

  @override
  State<PagedVideoBrowser> createState() => _PagedVideoBrowserState();
}

class _PagedVideoBrowserState extends State<PagedVideoBrowser> {
  final ScrollController _scroll = ScrollController();

  int _appPage = 1;
  int _serverPageSize = 0; // de-duplicated count of server page 1
  int _totalServerPages = 1;
  List<VideoItem> _items = <VideoItem>[];
  bool _loading = true;
  String? _error;

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

  /// How many server pages make up one app-page.
  int get _serverPagesPerApp {
    final s = _serverPageSize > 0 ? _serverPageSize : 24;
    return math.max(1, (widget.pageSize / s).ceil());
  }

  int get _appTotalPages {
    final k = _serverPagesPerApp;
    return math.max(1, (_totalServerPages / k).ceil());
  }

  Future<void> _load(int appPage) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final k = _serverPagesPerApp;
      final s1 = (appPage - 1) * k + 1;
      final s2 = appPage * k;

      final buffer = <VideoItem>[];
      for (var sp = s1; sp <= s2; sp++) {
        if (sp < 1) continue;
        if (_serverPageSize > 0 && sp > _totalServerPages) break;
        final r = await widget.fetch(sp);
        if (_serverPageSize <= 0) {
          _serverPageSize = r.items.isNotEmpty ? r.items.length : 24;
        }
        if (r.totalPage > _totalServerPages) _totalServerPages = r.totalPage;
        buffer.addAll(r.items);
        // Stop early if a page came back empty (past the real end).
        if (r.items.isEmpty) break;
      }

      _items = _dedupe(buffer);
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

  /// Collapse duplicates by viewKey OR real video id (thumbnail id), whichever
  /// matches first. Keeps the first occurrence.
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
    final total = _appTotalPages;
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('跳到第几页'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 - $total'),
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
      final p = result.clamp(1, total).toInt();
      if (p != _appPage) _load(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const StatusView(loading: true);
    if (_error != null) return StatusView(error: _error, onRetry: () => _load(_appPage));
    if (_items.isEmpty) return StatusView(empty: true, emptyText: widget.emptyText);

    return Column(
      children: [
        Expanded(
          child: GridView.builder(
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
    final total = _appTotalPages;
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
            Text('第 $_appPage / $total 页 · 本页 ${_items.length} 个',
                style: const TextStyle(fontSize: 13)),
            IconButton(
              tooltip: '下一页',
              onPressed: _appPage < total ? () => _load(_appPage + 1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
            TextButton(onPressed: _promptJump, child: const Text('跳转')),
          ],
        ),
      ),
    );
  }
}
