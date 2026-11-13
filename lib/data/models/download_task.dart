enum DownloadStatus { queued, downloading, paused, completed, failed }

class DownloadTask {
  final String viewKey;
  final String title;
  final String cover;
  final String url;
  final String path;
  final int totalBytes;
  final int receivedBytes;
  final int speed; // bytes/sec
  final DownloadStatus status;

  const DownloadTask({
    required this.viewKey,
    required this.title,
    required this.cover,
    required this.url,
    required this.path,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.speed = 0,
    this.status = DownloadStatus.queued,
  });

  double get progress =>
      totalBytes <= 0 ? 0 : ((receivedBytes / totalBytes).clamp(0.0, 1.0) as num).toDouble();

  bool get isDone => status == DownloadStatus.completed;

  DownloadTask copyWith({
    int? totalBytes,
    int? receivedBytes,
    int? speed,
    DownloadStatus? status,
    String? path,
  }) =>
      DownloadTask(
        viewKey: viewKey,
        title: title,
        cover: cover,
        url: url,
        path: path ?? this.path,
        totalBytes: totalBytes ?? this.totalBytes,
        receivedBytes: receivedBytes ?? this.receivedBytes,
        speed: speed ?? this.speed,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'viewKey': viewKey,
        'title': title,
        'cover': cover,
        'url': url,
        'path': path,
        'totalBytes': totalBytes,
        'receivedBytes': receivedBytes,
        'speed': speed,
        'status': status.index,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> j) => DownloadTask(
        viewKey: (j['viewKey'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        cover: (j['cover'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        path: (j['path'] ?? '') as String,
        totalBytes: (j['totalBytes'] ?? 0) as int,
        receivedBytes: (j['receivedBytes'] ?? 0) as int,
        speed: (j['speed'] ?? 0) as int,
        status: DownloadStatus.values[(j['status'] ?? 0) as int],
      );
}
