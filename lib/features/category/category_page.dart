import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/settings_controller.dart';
import '../../data/repositories/video_repository.dart';
import '../../shared/widgets/paged_video_browser.dart';
import '../detail/detail_page.dart';
import '../search/search_page.dart';

class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});
  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  String _category = 'rf';
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<VideoRepository>();
    final pageSize = context.watch<SettingsController>().pageSize;
    final entries = ApiConstants.categories.entries.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('分类'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              repo.clearCache();
              setState(() => _nonce++);
            },
          ),
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
            child: PagedVideoBrowser(
              key: ValueKey('$_category-$pageSize-$_nonce'),
              pageSize: pageSize,
              fetch: (serverPage) => repo.category(_category, serverPage),
              onItemTap: (item) => openDetail(context, item),
            ),
          ),
        ],
      ),
    );
  }
}
