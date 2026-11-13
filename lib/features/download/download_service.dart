import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/models/download_task.dart';
import '../../data/models/video_item.dart';
import '../../data/repositories/library_repository.dart';

/// Sequential-friendly download manager with pause / resume / cancel.
/// Replaces Android's FileDownloader + HttpProxyCacheServer combo with a single
/// Dio-based implementation that works identically on iOS.
class DownloadService extends ChangeNotifier {
  DownloadService({required this.library, Dio? dio}) : _dio = dio ?? Dio();

  final LibraryRepository library;
  final Dio _dio;

  final Map<String, CancelToken> _tokens = <String, CancelToken>{};
  final Map<String, int> _lastBytes = <String, int>{};
  final Map<String, DateTime> _lastTick = <String, DateTime>{};

  List<DownloadTask> tasks = <DownloadTask>[];

  void load() {
    tasks = library.getDownloads();
    notifyListeners();
  }

  DownloadTask? taskOf(String viewKey) {
    for (final t in tasks) {
      if (t.viewKey == viewKey) return t;
    }
    return null;
  }

  bool isDownloading(String viewKey) =>
      taskOf(viewKey)?.status == DownloadStatus.downloading;

  Future<void> start(VideoItem item, ResolvedSource src) async {
    final existing = library.downloadOf(item.viewKey);
    if (existing != null && existing.status == DownloadStatus.completed) return;
    if (existing != null && existing.status == DownloadStatus.downloading) return;

    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/p91_downloads');
    if (!await folder.exists()) await folder.create(recursive: true);
    final path = '${folder.path}/${item.viewKey}.mp4';

    var task = DownloadTask(
      viewKey: item.viewKey,
      title: item.title,
      cover: item.cover,
      url: src.url,
      path: path,
      status: DownloadStatus.downloading,
    );
    _upsert(task);

    final token = CancelToken();
    _tokens[item.viewKey] = token;
    _lastBytes[item.viewKey] = 0;
    _lastTick[item.viewKey] = DateTime.now();

    try {
      await _dio.download(
        src.url,
        path,
        cancelToken: token,
        options: Options(headers: src.headers),
        onReceiveProgress: (received, total) {
          final now = DateTime.now();
          final prevTick = _lastTick[item.viewKey] ?? now;
          final prevBytes = _lastBytes[item.viewKey] ?? 0;
          final dt = now.difference(prevTick).inMilliseconds;
          final speed = dt > 0 ? ((received - prevBytes) * 1000 / dt).round() : 0;
          if (dt > 400) {
            _lastTick[item.viewKey] = now;
            _lastBytes[item.viewKey] = received;
          }
          final cur = taskOf(item.viewKey);
          if (cur == null) return;
          task = cur.copyWith(
            receivedBytes: received,
            totalBytes: total > 0 ? total : cur.totalBytes,
            speed: speed < 0 ? 0 : speed,
            status: DownloadStatus.downloading,
          );
          _replace(task);
        },
      );
      task = task.copyWith(
        status: DownloadStatus.completed,
        receivedBytes: task.totalBytes > 0 ? task.totalBytes : task.receivedBytes,
        speed: 0,
      );
      _replace(task);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        task = task.copyWith(status: DownloadStatus.paused, speed: 0);
      } else {
        task = task.copyWith(status: DownloadStatus.failed, speed: 0);
      }
      _replace(task);
    } catch (_) {
      task = task.copyWith(status: DownloadStatus.failed, speed: 0);
      _replace(task);
    } finally {
      _tokens.remove(item.viewKey);
    }
  }

  void pause(String viewKey) {
    _tokens[viewKey]?.cancel('paused');
    _tokens.remove(viewKey);
  }

  Future<void> resume(VideoItem item, ResolvedSource src) => start(item, src);

  Future<void> remove(String viewKey, {bool deleteFile = true}) async {
    pause(viewKey);
    final t = library.downloadOf(viewKey);
    if (deleteFile && t != null) {
      final f = File(t.path);
      if (await f.exists()) await f.delete();
    }
    tasks.removeWhere((e) => e.viewKey == viewKey);
    await library.removeDownload(viewKey);
    notifyListeners();
  }

  void _upsert(DownloadTask task) {
    tasks.removeWhere((e) => e.viewKey == task.viewKey);
    tasks.insert(0, task);
    library.upsertDownload(task);
    notifyListeners();
  }

  void _replace(DownloadTask task) {
    final i = tasks.indexWhere((e) => e.viewKey == task.viewKey);
    if (i >= 0) {
      tasks[i] = task;
    } else {
      tasks.insert(0, task);
    }
    library.upsertDownload(task);
    notifyListeners();
  }
}
