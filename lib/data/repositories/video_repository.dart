import '../models/video_item.dart';
import '../source/direct_link_cache.dart';
import '../source/p91_api.dart';
import '../source/proxy_pool.dart';
import 'library_repository.dart';

/// Facade the UI talks to. Wraps [P91Api], keeps a small in-memory *page* cache
/// (list pages) and a disk *direct-link* cache (resolved media URLs, valid
/// until the signed URL's `e=` expiry).
class VideoRepository {
  VideoRepository({P91Api? api, LibraryRepository? library})
      : api = api ?? P91Api(),
        library = library ?? LibraryRepository();

  final P91Api api;
  final LibraryRepository library;
  final DirectLinkCache directLinks = DirectLinkCache();

  final Map<String, PagedResult> _cache = <String, PagedResult>{};

  String get host => api.host;
  set host(String value) => api.host = value;

  Future<PagedResult> home({bool refresh = false}) async {
    const key = 'home';
    if (!refresh && _cache.containsKey(key)) return _cache[key]!;
    final r = await api.fetchHome();
    _cache[key] = r;
    return r;
  }

  Future<PagedResult> category(String category, int page,
      {bool refresh = false}) async {
    final key = 'cat:$category:$page';
    if (!refresh && _cache.containsKey(key)) return _cache[key]!;
    final r = await api.fetchCategory(category, page);
    _cache[key] = r;
    return r;
  }

  Future<PagedResult> search(String keyword, int page) =>
      api.search(keyword, page);

  Future<VideoItem> detail(String viewKey) => api.fetchDetail(viewKey);

  /// Resolve a playable source, using the disk cache while the signed URL is
  /// still valid. `forceRefresh: true` bypasses the cache (e.g. user tap "重试"
  /// after playback failed with 403).
  Future<ResolvedSource> resolve(String viewKey, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = directLinks.get(viewKey);
      if (cached != null) return cached;
    }
    final src = await api.resolveSource(viewKey);
    await directLinks.put(viewKey, src);
    return src;
  }

  Future<ResolvedSource> resolveFromUrl(String pageUrl) =>
      api.resolveFromPageUrl(pageUrl);

  void clearCache() => _cache.clear();

  /// Apply the daily-10 bypass + mirror-challenge settings.
  void configureBypass({
    required bool enabled,
    required String proxyPoolText,
    required int maxAttempts,
    bool webviewFallback = true,
  }) {
    api.configure(
      bypassEnabled: enabled,
      webviewFallback: webviewFallback,
      proxyPool: ProxyPool.parse(proxyPoolText),
      maxAttempts: maxAttempts,
    );
    _cache.clear();
  }
}
