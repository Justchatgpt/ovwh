import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/video_repository.dart';
import '../../shared/widgets/paged_video_grid.dart';
import '../detail/detail_page.dart';
import '../search/search_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.read<VideoRepository>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('P91', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SearchPage()),
            ),
          ),
        ],
      ),
      body: PagedVideoGrid(
        fetcher: (page) => repo.category('rf', page, refresh: page == 1),
        onItemTap: (item) => openDetail(context, item),
      ),
    );
  }
}
