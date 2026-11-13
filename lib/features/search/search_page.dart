import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/video_repository.dart';
import '../../shared/widgets/paged_video_grid.dart';
import '../../shared/widgets/status_view.dart';
import '../detail/detail_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _text = TextEditingController();
  String _submitted = '';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _search() {
    final kw = _text.text.trim();
    if (kw.isEmpty) return;
    setState(() => _submitted = kw);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<VideoRepository>();
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _text,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: const InputDecoration(
            hintText: '搜索视频关键词',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _search),
        ],
      ),
      body: _submitted.isEmpty
          ? const StatusView(empty: true, emptyText: '输入关键词开始搜索')
          : PagedVideoGrid(
              key: ValueKey(_submitted),
              fetcher: (page) => repo.search(_submitted, page),
              onItemTap: (item) => openDetail(context, item),
              emptyText: '没有找到相关视频',
            ),
    );
  }
}
