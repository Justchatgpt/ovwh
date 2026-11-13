import 'package:flutter/material.dart';

import '../../data/models/video_item.dart';
import 'status_view.dart';
import 'video_grid.dart';

/// A self-contained, pull-to-refresh + infinite-scroll video grid.
/// Pages only supply a [fetcher] that returns a [PagedResult] for a page index.
class PagedVideoGrid extends StatefulWidget {
  const PagedVideoGrid({
    super.key,
    required this.fetcher,
    required this.onItemTap,
    this.headerSlivers = const <Widget>[],
    this.emptyText = '暂无内容',
    this.onItemLongPress,
  });

  final Future<PagedResult> Function(int page) fetcher;
  final void Function(VideoItem item) onItemTap;
  final void Function(VideoItem item)? onItemLongPress;
  final List<Widget> headerSlivers;
  final String emptyText;

  @override
  State<PagedVideoGrid> createState() => _PagedVideoGridState();
}

class _PagedVideoGridState extends State<PagedVideoGrid> {
  final ScrollController _controller = ScrollController();
  final List<VideoItem> _items = <VideoItem>[];
  int _page = 0;
  int _totalPage = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _first();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) _more();
  }

  Future<void> _first() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.fetcher(1);
      _items
        ..clear()
        ..addAll(r.items);
      _page = 1;
      _totalPage = r.totalPage;
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_loadingMore || _page >= _totalPage) return;
    setState(() => _loadingMore = true);
    try {
      final r = await widget.fetcher(_page + 1);
      if (r.items.isEmpty) {
        _totalPage = _page;
      } else {
        _items.addAll(r.items);
        _page += 1;
        _totalPage = r.totalPage;
      }
    } catch (_) {
      // silent: user can scroll again
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const StatusView(loading: true);
    }
    if (_error != null && _items.isEmpty) {
      return StatusView(error: _error, onRetry: _first);
    }
    return RefreshIndicator(
      onRefresh: _first,
      child: CustomScrollView(
        controller: _controller,
        slivers: [
          ...widget.headerSlivers,
          if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: StatusView(empty: true, emptyText: widget.emptyText),
            )
          else
            videoGridSliver(
              _items,
              onTap: widget.onItemTap,
              onLongPress: widget.onItemLongPress,
            ),
          SliverToBoxAdapter(
            child: _loadingMore
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : const SizedBox(height: 24),
          ),
        ],
      ),
    );
  }
}
