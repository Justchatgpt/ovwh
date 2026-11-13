import 'package:flutter/material.dart';

import '../../data/models/video_item.dart';
import 'video_card.dart';

const SliverGridDelegate videoGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 230,
  childAspectRatio: 0.82,
  crossAxisSpacing: 10,
  mainAxisSpacing: 16,
);

/// Builds a sliver grid of [VideoCard]s for use inside a CustomScrollView.
Widget videoGridSliver(
  List<VideoItem> items, {
  required ValueChanged<VideoItem> onTap,
  ValueChanged<VideoItem>? onLongPress,
  EdgeInsets padding = const EdgeInsets.fromLTRB(12, 8, 12, 8),
}) {
  return SliverPadding(
    padding: padding,
    sliver: SliverGrid(
      gridDelegate: videoGridDelegate,
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          final it = items[i];
          return VideoCard(
            item: it,
            onTap: () => onTap(it),
            onLongPress: onLongPress == null ? null : () => onLongPress(it),
          );
        },
        childCount: items.length,
      ),
    ),
  );
}
