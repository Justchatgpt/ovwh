import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/video_item.dart';
import '../../data/repositories/video_repository.dart';
import '../../shared/widgets/status_view.dart';
import '../../shared/widgets/video_card.dart';
import '../../shared/widgets/video_grid.dart';
import '../detail/detail_page.dart';

/// "Filter by publish date" → pick a date, jump to the list page whose real
/// publish date first reaches that day, then browse it (prev/next page).
///
/// Only the chronological category「最近更新(rf)」is offered here: the other
/// categories are sorted by popularity/duration, NOT by time, so a date seek
/// on them is meaningless.
class TimeFilterPage extends StatefulWidget {
  const TimeFilterPage({super.key});

  @override
  State<TimeFilterPage> createState() => _TimeFilterPageState();
}

class _TimeFilterPageState extends State<TimeFilterPage> {
  static const String _category = 'rf';

  DateTime _date = DateTime.now();
  bool _loading = false;
  String _status = '';
  String? _error;
  int _page = 1;
  DateTime? _pageDate;
  List<VideoItem> _items = <VideoItem>[];
  bool _started = false;
  bool _notFound = false;

  static String _fmt(DateTime? d) => d == null
      ? '未知'
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015, 1, 1),
      lastDate: DateTime.now(),
      helpText: '选择发布日期',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _quick(int daysAgo) async {
    setState(() => _date = DateTime.now().subtract(Duration(days: daysAgo)));
    await _seek();
  }

  Future<void> _seek() async {
    final repo = context.read<VideoRepository>();
    setState(() {
      _loading = true;
      _error = null;
      _started = true;
      _status = '正在按日期定位…';
      _items = <VideoItem>[];
      _pageDate = null;
      _notFound = false;
    });
    try {
      final res = await repo.seekPageForDate(_category, _date);
      final pr = await repo.category(_category, res.page);
      if (!mounted) return;
      setState(() {
        _page = res.page;
        _pageDate = res.pageDate;
        _items = _dedupe(pr.items);
        _notFound = !res.matched;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _gotoPage(int page) async {
    if (page < 1) return;
    final repo = context.read<VideoRepository>();
    setState(() {
      _loading = true;
      _error = null;
      _status = '加载第 $page 页…';
      _notFound = false;
    });
    try {
      final pr = await repo.category(_category, page);
      final d = await repo.firstItemDate(_category, page);
      if (!mounted) return;
      setState(() {
        _page = page;
        _pageDate = d;
        _items = _dedupe(pr.items);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('按发布时间筛选')),
      body: Column(
        children: [
          _controls(),
          const Divider(height: 1),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 16, color: Colors.white60),
              const SizedBox(width: 6),
              Expanded(
                child: Text('分类：最近更新（仅此分类按发布时间排序）',
                    style: TextStyle(fontSize: 12, color: Colors.white60)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.event),
                label: Text(_fmt(_date)),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _seek,
                icon: const Icon(Icons.south_east),
                label: const Text('跳转'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ActionChip(label: const Text('今天'), onPressed: _loading ? null : () => _quick(0)),
              ActionChip(label: const Text('3天前'), onPressed: _loading ? null : () => _quick(3)),
              ActionChip(label: const Text('7天前'), onPressed: _loading ? null : () => _quick(7)),
              ActionChip(label: const Text('一年前'), onPressed: _loading ? null : () => _quick(365)),
              ActionChip(label: const Text('两年前'), onPressed: _loading ? null : () => _quick(730)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(_status, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
    }
    if (_error != null) {
      return StatusView(error: _error, onRetry: _started ? _seek : null);
    }
    if (!_started) {
      return const StatusView(empty: true, emptyText: '选择日期，点“跳转”定位');
    }
    return Column(
      children: [
        if (_notFound) _banner(),
        Expanded(
          child: _items.isEmpty
              ? const StatusView(empty: true, emptyText: '该页没有内容，可换日期或返回')
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  gridDelegate: videoGridDelegate,
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    return VideoCard(item: item, onTap: () => openDetail(context, item));
                  },
                ),
        ),
        _pager(),
      ],
    );
  }

  Widget _banner() {
    return Container(
      width: double.infinity,
      color: Colors.amber.withOpacity(0.15),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text('所选日期早于「最近更新」可回溯的范围，已定位到最早一页（约 ${_fmt(_pageDate)}）',
          style: const TextStyle(fontSize: 12, color: Colors.amber)),
    );
  }

  Widget _pager() {
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
              tooltip: '上一页（更新）',
              onPressed: _page > 1 ? () => _gotoPage(_page - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Flexible(
              child: Text('第 $_page 页 · 约 ${_fmt(_pageDate)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13)),
            ),
            IconButton(
              tooltip: '下一页（更早）',
              onPressed: () => _gotoPage(_page + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
