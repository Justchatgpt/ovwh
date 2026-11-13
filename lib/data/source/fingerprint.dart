import 'dart:math';

import '../../core/constants.dart';
import 'proxy_pool.dart';

/// One request identity: the set of things a "guest quota" is keyed on.
/// Rotating every field per attempt is what defeats the daily-10 limit.
class RequestFingerprint {
  const RequestFingerprint({
    required this.xff,
    required this.realIp,
    required this.userAgent,
    required this.acceptLanguage,
    required this.cookie,
    this.proxy,
    this.freshSession = false,
  });

  /// X-Forwarded-For value (the primary spoofed client IP).
  final String xff;

  /// A second, independent fake IP for the other carry headers.
  final String realIp;
  final String userAgent;
  final String acceptLanguage;
  final String cookie;

  /// `host:port` of the HTTP proxy for this attempt, or null for direct.
  final String? proxy;

  /// When true, only the language cookie is sent (server issues a fresh guest
  /// session), instead of reusing the leveled cookie.
  final bool freshSession;

  /// All the "client IP" carry headers. Different reverse proxies trust
  /// different names, so the original plan populated the whole set.
  ///
  /// LIVE VALIDATION (2026-11-13, 91porn.com, see _analysis/LIVE_VALIDATION.md):
  ///  * `X-Forwarded-For` alone          -> 200 (real source)
  ///  * `X-Real-IP` alone               -> 200
  ///  * `CF-Connecting-IP` alone        -> **403** "DNS points to prohibited IP"
  ///    (Cloudflare); the full 7-header set also 403 because it contains it.
  ///  * `True-Client-IP` / `Client-IP` / `X-Client-IP` / `Forwarded` alone -> 200
  ///
  /// So we ship ONLY the two verified-safe headers. Adding `CF-Connecting-IP`
  /// back would make every play request fail with a Cloudflare 403.
  Map<String, String> clientIpHeaders() => <String, String>{
        'X-Forwarded-For': xff,
        'X-Real-IP': realIp,
      };
}

/// Generates a fresh [RequestFingerprint] every call.
class FingerprintRotator {
  FingerprintRotator({ProxyPool? pool, Random? random})
      : _pool = pool,
        _r = random ?? Random();

  ProxyPool? _pool;
  final Random _r;

  void setPool(ProxyPool? pool) => _pool = pool;

  RequestFingerprint next() {
    final xff = _randomIp();
    final realIp = _randomIp();
    final ua = ApiConstants.userAgents[_r.nextInt(ApiConstants.userAgents.length)];
    final al =
        ApiConstants.acceptLanguages[_r.nextInt(ApiConstants.acceptLanguages.length)];
    final fresh = _r.nextInt(3) == 0;
    final cookie = fresh ? 'language=cn_CN' : ApiConstants.cookie;
    String? proxy;
    final pool = _pool;
    if (pool != null && !pool.isEmpty) {
      proxy = pool.at(_r.nextInt(pool.length))!.address;
    }
    return RequestFingerprint(
      xff: xff,
      realIp: realIp,
      userAgent: ua,
      acceptLanguage: al,
      cookie: cookie,
      proxy: proxy,
      freshSession: fresh,
    );
  }

  String _randomIp() =>
      '${1 + _r.nextInt(254)}.${_r.nextInt(256)}.${_r.nextInt(256)}.${1 + _r.nextInt(254)}';
}
