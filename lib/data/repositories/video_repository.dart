import '../models/video_item.dart';
import '../source/direct_link_cache.dart';
import '../source/p91_api.dart';
import '../source/proxy_pool.dart';
import 'library_repository.dart';

/// Result of a publish-date seek.
class DateSeekResult {
  DateSeekResult({required this.page, required this.pageDate, required this.matched});
  final int page;
  final DateTime? pageDate;

  /// True when a page whose date is at/older than the target was found.
  final bool matched;
}

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

  final Map<String, DateTime?> _dateCache = <String, DateTime?>{};

  Future<DateTime?> _dateOf(String viewKey) async {
    if (_dateCache.containsKey(viewKey)) return _dateCache[viewKey];
    final d = await api.publishDate(viewKey);
    _dateCache[viewKey] = d;
    return d;
  }

  /// Publish date of the first (newest) item on a category page.
  Future<DateTime?> firstItemDate(String category, int page) async {
    final r = await this.category(category, page);
    if (r.items.isEmpty) return null;
    return _dateOf(r.items.first.viewKey);
  }

  /// Find the first category page whose newest item is at/older than [target].
  ///
  /// We LINEAR-SCAN from page 1 (not binary search): the date is only coarse
  /// per page and older pages are a huge "same date" plateau, so binary search
  /// lands on a wrong deep page. For a chronological category the boundary is
  /// within the first ~dozen pages for the recent ~2 weeks, so a bounded linear
  /// scan is both accurate and cheap. Returns [matched]=false when the target
  /// is older than anything reachable within [maxScan] pages (caller shows the
  /// earliest available date).
  Future<DateSeekResult> seekPageForDate(String category, DateTime target,
      {int maxScan = 20}) async {
    final tMid = DateTime(target.year, target.month, target.day);
    DateTime? lastDate;
    var lastPageWithItems = 1;
    for (var p = 1; p <= maxScan; p++) {
      final r = await this.category(category, p);
      if (r.items.isEmpty) break;
      lastPageWithItems = p;
      final d = await _dateOf(r.items.first.viewKey);
      if (d == null) continue;
      lastDate = d;
      if (d.isAfter(tMid)) {
        continue; // still newer than target -> go deeper
      }
      return DateSeekResult(page: p, pageDate: d, matched: true);
    }
    return DateSeekResult(page: lastPageWithItems, pageDate: lastDate, matched: false);
  }

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
