import 'dart:convert';

/// A single video entry as shown in list / grid / detail.
///
/// Field set intentionally matches the union of the three original models:
///  - Android `UnLimit91PornItem` (viewKey,title,imgUrl,duration,info,videoUrl)
///  - iOS `PornItem` / `VideoResult`
class VideoItem {
  final String viewKey;
  final String title;
  final String cover;
  final String duration; // display string, e.g. "12:30"
  final int durationSeconds;
  final String info; // "添加时间: ..." / "作者: ..."
  final String pageUrl;
  final String ownerName;

  const VideoItem({
    required this.viewKey,
    required this.title,
    this.cover = '',
    this.duration = '',
    this.durationSeconds = 0,
    this.info = '',
    this.pageUrl = '',
    this.ownerName = '',
  });

  VideoItem copyWith({
    String? title,
    String? cover,
    String? duration,
    int? durationSeconds,
    String? info,
    String? pageUrl,
    String? ownerName,
  }) {
    return VideoItem(
      viewKey: viewKey,
      title: title ?? this.title,
      cover: cover ?? this.cover,
      duration: duration ?? this.duration,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      info: info ?? this.info,
      pageUrl: pageUrl ?? this.pageUrl,
      ownerName: ownerName ?? this.ownerName,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'viewKey': viewKey,
        'title': title,
        'cover': cover,
        'duration': duration,
        'durationSeconds': durationSeconds,
        'info': info,
        'pageUrl': pageUrl,
        'ownerName': ownerName,
      };

  factory VideoItem.fromJson(Map<String, dynamic> j) => VideoItem(
        viewKey: (j['viewKey'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        cover: (j['cover'] ?? '') as String,
        duration: (j['duration'] ?? '') as String,
        durationSeconds: (j['durationSeconds'] ?? 0) as int,
        info: (j['info'] ?? '') as String,
        pageUrl: (j['pageUrl'] ?? '') as String,
        ownerName: (j['ownerName'] ?? '') as String,
      );

  static VideoItem fromJsonString(String s) =>
      VideoItem.fromJson(jsonDecode(s) as Map<String, dynamic>);

  String toJsonString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is VideoItem && other.viewKey == viewKey;

  @override
  int get hashCode => viewKey.hashCode;
}

/// A page of results with pagination metadata.
class PagedResult {
  final List<VideoItem> items;
  final int page;
  final int totalPage;

  const PagedResult({
    required this.items,
    required this.page,
    required this.totalPage,
  });

  bool get hasMore => page < totalPage;

  static const PagedResult empty =
      PagedResult(items: <VideoItem>[], page: 1, totalPage: 1);
}

/// A resolved, directly playable media source.
class ResolvedSource {
  final String url;
  final String name;
  final Map<String, String> headers;
  final String? videoId;

  const ResolvedSource({
    required this.url,
    required this.name,
    this.headers = const <String, String>{},
    this.videoId,
  });

  bool get isPlayable => url.isNotEmpty;
}
