import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/video_item.dart';
import '../../data/repositories/video_repository.dart';
import '../../shared/widgets/status_view.dart';
import '../../shared/widgets/video_card.dart';
import '../../shared/widgets/video_grid.dart';
import '../detail/detail_page.dart';

/// "Filter by publish date" → browse the WHOLE archive for a chosen day via
/// `search_result.php?search_type=date`, which works for any historical date
/// (one year / two years ago included). Supports paging within that day.
class TimeFilterPage extends StatefulWidget {
  const TimeFilterPage({super.key});

  @override
  State<TimeFilterPage> createState() => _TimeFilterPageState();
}

class _TimeFilterPageState extends State<TimeFilterPage> {
  DateTime _date = DateTime.now();
  bool _loading = false;
  String _status = '';
  String? _error;
  int _page = 1;
  int? _totalPages;
  List<VideoItem> _items = <VideoItem>[];
  bool _started = false;

  static String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015, 1, 1),
      lastDate: DateTime.now(),
      helpText: '选择发布日期',
    );
    if (picked != null) {
      setState(() => _date = picked);
      await _run(1);
    }
  }

  Future<void> _quick(int daysAgo) async {
    setState(() => _date = DateTime.now().subtract(Duration(days: daysAgo)));
    await _run(1);
  }

  bool get _canNextDay {
    final tomorrow = DateTime(_date.year, _date.month, _date.day).add(const Duration(days: 1));
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return !tomorrow.isAfter(today);
  }

  Future<void> _shiftDay(int delta) async {
    if (_loading) return;
    final nd = DateTime(_date.year, _date.month, _date.day).add(Duration(days: delta));
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (nd.isAfter(today)) return;
    setState(() => _date = nd);
    await _run(1);
  }

  Future<void> _run(int page) async {
    final repo = context.read<VideoRepository>();
    setState(() {
      _loading = true;
      _error = null;
      _started = true;
      _status = '正在检索 ${_fmt(_date)} 的视频…';
    });
    try {
      final pr = await repo.searchByDate(_date, page);
      if (!mounted) return;
      setState(() {
        _page = page;
        _items = _dedupe(pr.items);
        _totalPages = pr.totalPage > 0 ? pr.totalPage : null;
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

  bool get _canNext {
    // Allow going further as long as the current page had results, so a wrong
    // total never blocks paging. Stops naturally on an empty page.
    return _items.isNotEmpty;
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
              const Icon(Icons.event_available, size: 16, color: Colors.white60),
              const SizedBox(width: 6),
              Expanded(
                child: Text('按发布日期检索全站历史（支持任意较早日期）',
                    style: TextStyle(fontSize: 12, color: Colors.white60)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _loading ? null : _pickDate,
                icon: const Icon(Icons.event),
                label: Text(_fmt(_date)),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _loading ? null : () => _run(1),
                icon: const Icon(Icons.search),
                label: const Text('检索'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _loading ? null : () => _shiftDay(-1),
                icon: const Icon(Icons.chevron_left),
                label: const Text('前一天'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: (_loading || !_canNextDay) ? null : () => _shiftDay(1),
                icon: const Icon(Icons.chevron_right),
                label: const Text('后一天'),
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
      return StatusView(error: _error, onRetry: () => _run(_page));
    }
    if (!_started) {
      return const StatusView(empty: true, emptyText: '选择日期，点“检索”查看该日视频');
    }
    if (_items.isEmpty && _page == 1) {
      return const StatusView(empty: true, emptyText: '该日期没有视频，换个日期试试');
    }
    return Column(
      children: [
        Expanded(
          child: _items.isEmpty
              ? const StatusView(empty: true, emptyText: '没有更多内容了，可返回上一页')
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

  Widget _pager() {
    final scheme = Theme.of(context).colorScheme;
    final totalPart = _totalPages != null ? ' / $_totalPages' : '';
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant.withOpacity(0.4))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: '上一页',
              onPressed: _page > 1 ? () => _run(_page - 1) : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Flexible(
              child: Text('${_fmt(_date)} · 第 $_page$totalPart 页 · 本页 ${_items.length} 个',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            ),
            IconButton(
              tooltip: '下一页',
              onPressed: _canNext ? () => _run(_page + 1) : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}
