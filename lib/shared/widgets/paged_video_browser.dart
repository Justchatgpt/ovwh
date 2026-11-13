import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/video_item.dart';
import 'status_view.dart';
import 'video_card.dart';
import 'video_grid.dart'; // videoGridDelegate

/// Explicit page-number browser for a 91 listing.
///
/// The site paginates server-side with a fixed count per page. We expose a
/// client-side "videos per page" size: the whole server stream is chunked into
/// consecutive windows of [pageSize] items, so the user can jump straight to an
/// old page (e.g. page 300) instead of infinite-scrolling forever.
///
/// Item N in the flat stream lives on server page `N ~/ serverPageSize + 1`;
/// to render app-page P we fetch exactly the server page(s) that cover
/// [start, end) and slice — so no items are dropped no matter how [pageSize]
/// compares to the server's page size.
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
  int _serverPageSize = 0; // measured from first server page
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

  int get _appTotalPages {
    if (_serverPageSize <= 0) return 1;
    final totalItems = _totalServerPages * _serverPageSize;
    return math.max(1, (totalItems / widget.pageSize).ceil());
  }

  Future<void> _load(int appPage) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_serverPageSize <= 0) {
        final first = await widget.fetch(1);
        _serverPageSize = first.items.isNotEmpty ? first.items.length : 20;
        _totalServerPages = math.max(1, first.totalPage);
        if (appPage == 1) {
          _items = first.items.take(widget.pageSize).toList();
          _appPage = 1;
          return;
        }
      }

      final start = (appPage - 1) * widget.pageSize;
      final end = start + widget.pageSize; // exclusive
      final s1 = (start ~/ _serverPageSize) + 1;
      final s2 = ((end - 1) ~/ _serverPageSize) + 1;

      final buffer = <VideoItem>[];
      for (var sp = s1; sp <= s2; sp++) {
        if (sp < 1) continue;
        final r = await widget.fetch(sp);
        if (r.totalPage > _totalServerPages) _totalServerPages = r.totalPage;
        buffer.addAll(r.items);
      }

      final base = (s1 - 1) * _serverPageSize;
      final offset = math.max(0, start - base);
      _items = _dedupe(buffer.skip(offset).take(widget.pageSize).toList());
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

  /// Guard against cross-page duplicates (same viewKey on adjacent server
  /// pages), preserving first-seen order.
  List<VideoItem> _dedupe(List<VideoItem> items) {
    final seen = <String>{};
    final out = <VideoItem>[];
    for (final it in items) {
      if (seen.add(it.viewKey)) out.add(it);
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
            Text('第 $_appPage / $total 页 · ${widget.pageSize} 个/页',
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
