import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings_controller.dart';
import '../../data/repositories/video_repository.dart';
import '../../shared/widgets/paged_video_browser.dart';
import '../detail/detail_page.dart';
import '../search/search_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _nonce = 0;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<VideoRepository>();
    final pageSize = context.watch<SettingsController>().pageSize;
    return Scaffold(
      appBar: AppBar(
        title: const Text('P91', style: TextStyle(fontWeight: FontWeight.w800)),
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
      body: PagedVideoBrowser(
        key: ValueKey('home-$pageSize-$_nonce'),
        pageSize: pageSize,
        fetch: (serverPage) => repo.category('rf', serverPage),
        onItemTap: (item) => openDetail(context, item),
      ),
    );
  }
}
