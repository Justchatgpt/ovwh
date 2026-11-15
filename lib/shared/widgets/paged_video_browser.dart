import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/video_item.dart';
import 'status_view.dart';
import 'video_card.dart';
import 'video_grid.dart'; // videoGridDelegate

/// Explicit page-number browser for a 91 listing.
///
/// Correctness notes (from live probing, 2026-11-15):
///  * Cards are duplicated / re-published under several viewKeys with the same
///    cover → de-dupe by viewKey AND real video id (thumbnail id).
///  * Server pages have variable de-duped counts → paginate by contiguous
///    blocks of `k = ceil(pageSize / serverPageSize)` server pages (no skips,
///    no in-page duplicates, O(k) fetches even when jumping).
///  * The real total page count is only sometimes available (header
///    "视频 1 - 24 共 N"). When it isn't, the pager switches to "unknown total"
///    mode: you can keep pressing next (until a page comes back empty) and jump
///    to any page number instead of being stuck at the ~11 links the site shows.
class PagedVideoBrowser extends StatefulWidget {
  const PagedVideoBrowser({
    super.key,
    required this.fetch,
    required this.pageSize,
    required this.onItemTap,
    this.emptyText = '暂无内容',
  });

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
  int _serverPageSize = 0;
  int? _totalServerPages; // null = unknown
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

  int get _serverPagesPerApp {
    final s = _serverPageSize > 0 ? _serverPageSize : 24;
    return math.max(1, (widget.pageSize / s).ceil());
  }

  int? get _appTotalPages {
    final total = _totalServerPages;
    if (total == null || total <= 0) return null;
    return math.max(1, (total / _serverPagesPerApp).ceil());
  }

  bool get _canNext {
    // Don't trust a (possibly wrong) total count; allow going further as long
    // as the last page had items. Stops naturally on an empty page.
    return _lastHadItems;
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
      var anyItems = false;
      for (var sp = s1; sp <= s2; sp++) {
        if (sp < 1) continue;
        final r = await widget.fetch(sp);
        if (_serverPageSize <= 0) {
          _serverPageSize = r.items.isNotEmpty ? r.items.length : 24;
        }
        if (r.totalPage > 0) {
          _totalServerPages = (_totalServerPages != null && _totalServerPages! > r.totalPage)
              ? _totalServerPages
              : r.totalPage;
        }
        buffer.addAll(r.items);
        if (r.items.isNotEmpty) anyItems = true;
        if (r.items.isEmpty) break;
      }

      _items = _dedupe(buffer);
      _lastHadItems = anyItems;
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
          decoration: InputDecoration(hintText: '1 - $maxPage'),
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
    final pageLabel = '第 $_appPage 页 · 本页 ${_items.length} 个';
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
            Text(pageLabel, style: const TextStyle(fontSize: 13)),
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
