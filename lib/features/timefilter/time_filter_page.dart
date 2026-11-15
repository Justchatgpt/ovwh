import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/video_item.dart';
import '../../data/repositories/video_repository.dart';
import '../../shared/widgets/status_view.dart';
import '../../shared/widgets/video_card.dart';
import '../../shared/widgets/video_grid.dart';
import '../detail/detail_page.dart';

/// "Filter by publish month": pick a year+month, then browse ALL videos of that
/// month with infinite scroll (auto-pagination). Implemented by walking the
/// month day-by-day using the date-search endpoint (each day may have several
/// pages), de-duplicating across the whole month.
class TimeFilterPage extends StatefulWidget {
  const TimeFilterPage({super.key});

  @override
  State<TimeFilterPage> createState() => _TimeFilterPageState();
}

class _TimeFilterPageState extends State<TimeFilterPage> {
  final ScrollController _scroll = ScrollController();

  late int _year;
  late int _month;
  bool _started = false;
  bool _loading = false; // initial load
  bool _loadingMore = false;
  bool _allLoaded = false;
  String? _error;

  List<DateTime> _days = <DateTime>[];
  int _dayIdx = 0;
  final List<VideoItem> _items = <VideoItem>[];
  final Set<String> _seen = <String>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_started || _loading || _loadingMore || _allLoaded) return;
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) _loadMoreDays();
  }

  List<DateTime> _daysOfMonth(int year, int month) {
    final first = DateTime(year, month, 1);
    final next = DateTime(year, month + 1, 1);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var last = next.subtract(const Duration(days: 1));
    if (last.isAfter(today)) last = today;
    final days = <DateTime>[];
    var d = first;
    while (!d.isAfter(last)) {
      days.add(d);
      d = d.add(const Duration(days: 1));
    }
    return days;
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    var y = _year;
    var m = _month;
    final res = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final years = [for (var yy = now.year; yy >= 2015; yy--) yy];
          return AlertDialog(
            title: const Text('选择月份'),
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: y,
                    items: [for (final yy in years) DropdownMenuItem(value: yy, child: Text('$yy 年'))],
                    onChanged: (v) => setSt(() => y = v ?? y),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: m,
                    items: [for (var mm = 1; mm <= 12; mm++) DropdownMenuItem(value: mm, child: Text('$mm 月'))],
                    onChanged: (v) => setSt(() => m = v ?? m),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(onPressed: () => Navigator.pop(ctx, DateTime(y, m, 1)), child: const Text('确定')),
            ],
          );
        },
      ),
    );
    if (res != null) {
      setState(() {
        _year = res.year;
        _month = res.month;
      });
      await _start();
    }
  }

  Future<void> _quick(int monthDelta) async {
    final base = DateTime(_year, _month + monthDelta, 1);
    setState(() {
      _year = base.year;
      _month = base.month;
    });
    await _start();
  }

  Future<void> _start() async {
    setState(() {
      _started = true;
      _loading = true;
      _error = null;
      _allLoaded = false;
      _loadingMore = false;
      _dayIdx = 0;
      _items.clear();
      _seen.clear();
      _days = _daysOfMonth(_year, _month);
    });
    if (_days.isEmpty) {
      setState(() {
        _loading = false;
        _allLoaded = true;
      });
      return;
    }
    await _loadMoreDays(initial: true);
  }

  Future<void> _loadMoreDays({bool initial = false}) async {
    if (_loadingMore || _allLoaded) return;
    _loadingMore = true;
    if (!initial && mounted) setState(() {});
    final repo = context.read<VideoRepository>();
    try {
      var daysLoaded = 0;
      while (_dayIdx < _days.length && daysLoaded < 2) {
        final day = _days[_dayIdx];
        var page = 1;
        var hasNext = true;
        while (hasNext) {
          final pr = await repo.searchByDate(day, page);
          if (pr.items.isEmpty) break;
          final fresh = _dedupeNew(pr.items);
          if (fresh.isNotEmpty && mounted) {
            setState(() => _items.addAll(fresh));
          }
          hasNext = pr.hasNext;
          page++;
          if (page > 40) break;
        }
        _dayIdx++;
        daysLoaded++;
        if (_items.length >= 48) break;
      }
      if (_dayIdx >= _days.length) _allLoaded = true;
    } catch (e) {
      if (mounted) _error = '$e';
    } finally {
      _loadingMore = false;
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  List<VideoItem> _dedupeNew(List<VideoItem> items) {
    final out = <VideoItem>[];
    for (final it in items) {
      final key = it.contentKey;
      if (_seen.contains(key)) continue;
      _seen.add(key);
      out.add(it);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('按月份浏览')),
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
              OutlinedButton.icon(
                onPressed: _loading ? null : _pickMonth,
                icon: const Icon(Icons.calendar_month),
                label: Text('$_year 年 $_month 月'),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _loading ? null : _start,
                icon: const Icon(Icons.search),
                label: const Text('加载'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ActionChip(label: const Text('本月'), onPressed: _loading ? null : () => _quick(0)),
              ActionChip(label: const Text('上月'), onPressed: _loading ? null : () => _quick(-1)),
              if (_started)
                Chip(
                  label: Text('已加载 ${_items.length} 个'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _content() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return StatusView(error: _error, onRetry: _start);
    }
    if (!_started) {
      return const StatusView(empty: true, emptyText: '选择年份和月份，点“加载”浏览整月视频');
    }
    if (_items.isEmpty && _allLoaded) {
      return const StatusView(empty: true, emptyText: '该月份没有视频');
    }
    final showLoader = !_allLoaded;
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      gridDelegate: videoGridDelegate,
      itemCount: _items.length + (showLoader ? 1 : 0),
      itemBuilder: (context, i) {
        if (i < _items.length) {
          final item = _items[i];
          return VideoCard(item: item, onTap: () => openDetail(context, item));
        }
        // Last cell = loading indicator; make sure more days get pulled in.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_loadingMore && !_allLoaded) _loadMoreDays();
        });
        return const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()));
      },
    );
  }
}
