import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../data/repositories/video_repository.dart';
import '../../shared/widgets/paged_video_grid.dart';
import '../detail/detail_page.dart';
import '../search/search_page.dart';

class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});
  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  String _category = 'rf';

  @override
  Widget build(BuildContext context) {
    final repo = context.read<VideoRepository>();
    final entries = ApiConstants.categories.entries.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              scrollDirection: Axis.horizontal,
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final e = entries[i];
                return ChoiceChip(
                  label: Text(e.value),
                  selected: _category == e.key,
                  onSelected: (_) => setState(() => _category = e.key),
                );
              },
            ),
          ),
          Expanded(
            child: PagedVideoGrid(
              key: ValueKey(_category),
              fetcher: (page) =>
                  repo.category(_category, page, refresh: page == 1),
              onItemTap: (item) => openDetail(context, item),
            ),
          ),
        ],
      ),
    );
  }
}
