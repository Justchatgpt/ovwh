import 'dart:convert';

import '../../core/storage.dart';
import '../models/download_task.dart';
import '../models/video_item.dart';

/// Local-first library: favorites, watch history and download tasks live in
/// Hive. This replaces the Android ObjectBox `UnLimit91PornItem` store and the
/// iOS FMDB cache with a single coherent model.
class LibraryRepository {
  // ---- Favorites -----------------------------------------------------------

  bool isFavorite(String viewKey) => LocalStore.favorites.containsKey(viewKey);

  Future<void> addFavorite(VideoItem item) async {
    final payload = <String, dynamic>{
      'item': item.toJson(),
      'favoriteDate': DateTime.now().millisecondsSinceEpoch,
    };
    await LocalStore.favorites.put(item.viewKey, jsonEncode(payload));
  }

  Future<void> removeFavorite(String viewKey) =>
      LocalStore.favorites.delete(viewKey);

  Future<bool> toggleFavorite(VideoItem item) async {
    if (isFavorite(item.viewKey)) {
      await removeFavorite(item.viewKey);
      return false;
    }
    await addFavorite(item);
    return true;
  }

  List<VideoItem> getFavorites() {
    final list = LocalStore.favorites.values
        .map((s) => jsonDecode(s as String) as Map<String, dynamic>)
        .toList()
      ..sort((a, b) => (b['favoriteDate'] as int).compareTo(a['favoriteDate'] as int));
    return list
        .map((m) => VideoItem.fromJson(m['item'] as Map<String, dynamic>))
        .toList();
  }

  // ---- History -------------------------------------------------------------

  Future<void> recordHistory(VideoItem item, {int positionMs = 0}) async {
    final payload = <String, dynamic>{
      'item': item.toJson(),
      'positionMs': positionMs,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await LocalStore.history.put(item.viewKey, jsonEncode(payload));
  }

  int historyPosition(String viewKey) {
    final raw = LocalStore.history.get(viewKey);
    if (raw == null) return 0;
    return (jsonDecode(raw as String)['positionMs'] ?? 0) as int;
  }

  List<VideoItem> getHistory() {
    final list = LocalStore.history.values
        .map((s) => jsonDecode(s as String) as Map<String, dynamic>)
        .toList()
      ..sort((a, b) => (b['updatedAt'] as int).compareTo(a['updatedAt'] as int));
    return list
        .map((m) => VideoItem.fromJson(m['item'] as Map<String, dynamic>))
        .toList();
  }

  Future<void> clearHistory() => LocalStore.history.clear();

  // ---- Downloads -----------------------------------------------------------

  Future<void> upsertDownload(DownloadTask task) =>
      LocalStore.downloads.put(task.viewKey, jsonEncode(task.toJson()));

  Future<void> removeDownload(String viewKey) =>
      LocalStore.downloads.delete(viewKey);

  List<DownloadTask> getDownloads() => LocalStore.downloads.values
      .map((s) => DownloadTask.fromJson(jsonDecode(s as String) as Map<String, dynamic>))
      .toList();

  DownloadTask? downloadOf(String viewKey) {
    final raw = LocalStore.downloads.get(viewKey);
    if (raw == null) return null;
    return DownloadTask.fromJson(jsonDecode(raw as String) as Map<String, dynamic>);
  }
}
