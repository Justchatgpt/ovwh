import 'dart:convert';

import '../../core/storage.dart';
import '../models/video_item.dart';

/// Caches resolved, directly-playable URLs per `viewKey` until the signed
/// URL's own expiry (`e=` query param, a Unix timestamp in seconds).
///
/// Why: 91 issues one-shot, time-limited signed URLs
/// (`...mp4?st=...&e=1794557857&k=...&f=...`). The `e` we observed is ~+2h.
/// Caching the resolved source until just before `e` means replaying the same
/// video never re-hits `view_video.php` → no new quota use, no extra latency.
/// This mirrors 9orn2's `saveVideoUrl` + `getVideoUrlByViewKey` (which cached
/// indefinitely) but is *correct* because we respect the real signature TTL.
class DirectLinkCache {
  /// Refresh a bit before the real expiry so a request never races the CDN.
  static const int _safetyMarginMs = 60 * 1000;

  /// If the URL has no `e=` param, cache for a conservative short window.
  static const int _defaultTtlMs = 5 * 60 * 1000;

  /// Extract the `e=<unix-seconds>` expiry from a signed media URL.
  static DateTime? expiryOf(String url) {
    final m = RegExp(r'[?&]e=(\d+)').firstMatch(url);
    if (m == null) return null;
    final secs = int.tryParse(m.group(1)!);
    if (secs == null || secs <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  }

  ResolvedSource? get(String viewKey) {
    final raw = LocalStore.directLinks.get(viewKey);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      final expiresAt = (j['expiresAt'] as num).toInt();
      if (DateTime.now().millisecondsSinceEpoch >= expiresAt) {
        LocalStore.directLinks.delete(viewKey);
        return null;
      }
      final headers = <String, String>{};
      final h = j['headers'];
      if (h is Map) {
        h.forEach((k, v) => headers['$k'] = '$v');
      }
      return ResolvedSource(
        url: j['url'] as String,
        name: (j['name'] as String?) ?? '91 直链',
        videoId: j['videoId'] as String?,
        headers: headers,
      );
    } catch (_) {
      LocalStore.directLinks.delete(viewKey);
      return null;
    }
  }

  /// Returns true if the entry was stored (i.e. still had a useful lifetime).
  Future<bool> put(String viewKey, ResolvedSource src) async {
    if (!src.isPlayable) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final exp = expiryOf(src.url);
    final expiresAt = exp != null
        ? exp.millisecondsSinceEpoch - _safetyMarginMs
        : now + _defaultTtlMs;
    if (expiresAt <= now + 5000) return false; // too short to be worth caching

    final payload = <String, dynamic>{
      'url': src.url,
      'name': src.name,
      'videoId': src.videoId,
      'headers': src.headers,
      'expiresAt': expiresAt,
    };
    await LocalStore.directLinks.put(viewKey, jsonEncode(payload));
    return true;
  }

  DateTime? expiresAtOf(String viewKey) {
    final raw = LocalStore.directLinks.get(viewKey);
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw as String) as Map<String, dynamic>;
      return DateTime.fromMillisecondsSinceEpoch((j['expiresAt'] as num).toInt());
    } catch (_) {
      return null;
    }
  }

  Future<void> purgeExpired() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final dead = <dynamic>[];
    for (final key in LocalStore.directLinks.keys) {
      final raw = LocalStore.directLinks.get(key);
      try {
        final j = jsonDecode(raw as String) as Map<String, dynamic>;
        if ((j['expiresAt'] as num).toInt() <= now) dead.add(key);
      } catch (_) {
        dead.add(key);
      }
    }
    for (final k in dead) {
      await LocalStore.directLinks.delete(k);
    }
  }

  Future<void> clear() => LocalStore.directLinks.clear();

  int get count => LocalStore.directLinks.length;
}
