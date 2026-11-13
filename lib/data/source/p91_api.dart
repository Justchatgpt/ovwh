import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/challenge_solver.dart';
import '../../core/constants.dart';
import '../models/video_item.dart';
import 'fingerprint.dart';
import 'p91_parser.dart';
import 'proxy_pool.dart';

/// HTTP client + source contract for the 91 site, with a built-in
/// daily-10-limit bypass engine.
///
/// How the limit works (reverse-engineered from 9orn2 `RandomIPAdderssUtils`
/// and the app-release.apk's browser-emulating request headers):
///  * 91 treats a "guest" as (client-IP, cookie-session, UA). A guest may open
///    a limited number of `view_video.php` pages per day; past that the page
///    returns the "你每天只可观看10个视频" notice instead of the source.
///  * The edge trusts client-IP carry headers (`X-Forwarded-For` etc.), so a
///    fresh fake IP per page load resets the counter — as long as the origin
///    trusts the header.
///
/// The bypass therefore rotates, per attempt:
///  1. client-IP carry headers (`X-Forwarded-For` + `X-Real-IP` only — adding
///     `CF-Connecting-IP` triggers a Cloudflare 403, see LIVE_VALIDATION.md),
///  2. the User-Agent (a 10-UA desktop pool),
///  3. the Accept-Language,
///  4. the cookie (sometimes issue a fresh guest session),
///  5. the mirror host, and
///  6. optionally a real HTTP proxy (real upstream IP) from the user pool.
/// If the origin ignores spoofed headers, only #6 (a real proxy) will move the
/// counter — hence the proxy pool in Settings.
class P91Api {
  P91Api({
    String? host,
    List<String>? hosts,
    ProxyPool? proxyPool,
    bool bypassEnabled = true,
    bool webviewFallback = true,
    int maxAttempts = 8,
    Dio? dio,
  }) {
    _host = _norm(host ?? ApiConstants.defaultHost);
    _extraHosts = (hosts ?? const <String>[]).map(_norm).where((e) => e.isNotEmpty).toList();
    _bypassEnabled = bypassEnabled;
    _webviewFallback = webviewFallback;
    _maxAttempts = maxAttempts;
    _proxyPool = proxyPool ?? ProxyPool(const <ProxyEntry>[]);
    _rotator = FingerprintRotator(pool: _proxyPool);
    _customDio = dio;
  }

  final Random _rand = Random();
  late String _host;
  late List<String> _extraHosts;
  late bool _bypassEnabled;
  late bool _webviewFallback;
  late int _maxAttempts;
  late ProxyPool _proxyPool;
  late FingerprintRotator _rotator;
  Dio? _customDio;

  final Map<String, Dio> _dioByProxy = <String, Dio>{};
  final Set<String> _warmedHosts = <String>{};

  /// Cookies harvested by the WKWebView challenge runner, keyed by host, merged
  /// into subsequent page requests so the "passed" session is reused.
  final Map<String, Map<String, String>> _webviewCookiesByHost =
      <String, Map<String, String>>{};

  String _lastAttemptLog = '';
  String get lastAttemptLog => _lastAttemptLog;

  bool get webviewFallbackEnabled => _webviewFallback;

  String get host => _host;

  set host(String value) {
    final v = _norm(value);
    if (v.isEmpty) return;
    _host = v;
    _warmedHosts.clear();
  }

  int get maxAttempts => _maxAttempts;
  bool get bypassEnabled => _bypassEnabled;

  /// Reconfigure the bypass engine at runtime (called from Settings).
  void configure({
    bool? bypassEnabled,
    bool? webviewFallback,
    ProxyPool? proxyPool,
    int? maxAttempts,
  }) {
    if (bypassEnabled != null) _bypassEnabled = bypassEnabled;
    if (webviewFallback != null) _webviewFallback = webviewFallback;
    if (maxAttempts != null) _maxAttempts = maxAttempts;
    if (proxyPool != null) {
      _proxyPool = proxyPool;
      _rotator.setPool(proxyPool);
    }
  }

  // ---------------------------------------------------------------------------
  // Dio construction (per-proxy adapter so findProxy applies per request)
  // ---------------------------------------------------------------------------

  static String _norm(String s) {
    var v = s.trim();
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  Dio _dioFor(String? proxy) {
    final key = proxy ?? '';
    final cached = _dioByProxy[key];
    if (cached != null) return cached;
    final dio = (proxy == null && _customDio != null) ? _customDio! : _createDio(proxy);
    dio.options
      ..connectTimeout = const Duration(seconds: 12)
      ..receiveTimeout = const Duration(seconds: 20)
      ..followRedirects = true;
    _dioByProxy[key] = dio;
    return dio;
  }

  Dio _createDio(String? proxy) {
    final dio = Dio();
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        // Some 91 mirrors use self-signed / mismatched certs.
        client.badCertificateCallback = (cert, host, port) => true;
        if (proxy != null && proxy.isNotEmpty) {
          client.findProxy = (_) => 'PROXY $proxy';
        }
        return client;
      },
    );
    return dio;
  }

  // ---------------------------------------------------------------------------
  // Headers
  // ---------------------------------------------------------------------------

  Map<String, String> _pageHeaders(RequestFingerprint fp, String host) {
    final h = <String, String>{
      'User-Agent': fp.userAgent,
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': fp.acceptLanguage,
      // LIVE VALIDATION: with `Referer: {host}/index.php` a bare
      // `view_video.php?viewkey=...` returns 404 ("page can not found").
      // With the v.php list referer (or no Referer) it returns 200 + source.
      'Referer': '$host/v.php?category=rf&viewtype=basic&page=1',
      'Cookie': fp.cookie,
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
    };
    h.addAll(fp.clientIpHeaders());
    // Reuse cookies harvested by the WKWebView challenge runner for this host.
    final webCookies = _webviewCookiesByHost[host];
    if (webCookies != null && webCookies.isNotEmpty) {
      final extra = webCookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
      h['Cookie'] = '${h['Cookie']}; $extra';
    }
    return h;
  }

  /// Headers the media player must attach to the .mp4 request, or the CDN 403s.
  Map<String, String> mediaHeaders([String? host]) {
    final h = host ?? _host;
    return <String, String>{
      'User-Agent': ApiConstants.userAgent,
      'Referer': '$h/',
      'Origin': h,
      'Cookie': ApiConstants.cookie,
    };
  }

  // ---------------------------------------------------------------------------
  // GET with fingerprint + proxy
  // ---------------------------------------------------------------------------

  Future<String> _getPage(
    String pathAndQuery, {
    RequestFingerprint? fp,
    String? host,
  }) async {
    final h = host ?? _host;
    final fingerprint = fp ?? _rotator.next();
    await _warmUp(h, fingerprint);
    final dio = _dioFor(fingerprint.proxy);
    final uri = Uri.parse('$h$pathAndQuery');
    final resp = await dio.getUri<String>(
      uri,
      options: Options(
        headers: _pageHeaders(fingerprint, h),
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    final body = resp.data ?? '';
    if (resp.statusCode != null && resp.statusCode! >= 400) {
      // A challenge interstitial can also surface as 403/503.
      final solved = await _tryWebviewChallenge(uri, fingerprint, h);
      if (solved != null) return solved;
      throw P91Exception('请求失败 HTTP ${resp.statusCode} ($h)');
    }
    // A 200 that is actually the "Redirecting…" anti-bot page (91 clone mirrors).
    if (_webviewFallback && ChallengeSolver.looksLikeChallenge(body)) {
      final solved = await _tryWebviewChallenge(uri, fingerprint, h);
      if (solved != null) return solved;
    }
    return body;
  }

  bool get _canUseWebview => !kIsWeb && Platform.isIOS;

  /// Run [uri] through the native hidden WKWebView, harvest cookies, and return
  /// the real page HTML (or null if unavailable / still gated).
  Future<String?> _tryWebviewChallenge(
    Uri uri,
    RequestFingerprint fp,
    String host,
  ) async {
    if (!_webviewFallback || !_canUseWebview) return null;
    try {
      final result = await ChallengeSolver.solve(
        url: uri.toString(),
        headers: _pageHeaders(fp, host),
        timeoutMs: 25000,
      );
      if (result == null) return null;
      if (result.cookies.isNotEmpty) {
        _webviewCookiesByHost.putIfAbsent(host, () => <String, String>{}).addAll(result.cookies);
      }
      if (result.html.isNotEmpty && !ChallengeSolver.looksLikeChallenge(result.html)) {
        // Persisted cookies let the *next* plain Dio request skip the gate.
        _warmedHosts.remove(host);
        return result.html;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _warmUp(String host, RequestFingerprint fp) async {
    if (_warmedHosts.contains(host)) return;
    try {
      await _dioFor(fp.proxy).getUri<String>(
        Uri.parse('$host/index.php'),
        options: Options(
          headers: _pageHeaders(fp, host),
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );
    } catch (_) {
      // Landing probe failure must not block real requests.
    }
    _warmedHosts.add(host);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<PagedResult> fetchCategory(String category, int page) async {
    final cat = ApiConstants.categories.containsKey(category) ? category : 'rf';
    final html = await _getPage('/v.php?category=$cat&viewtype=basic&page=$page');
    return _toPaged(html, page);
  }

  /// Home = the featured block on index.php; falls back to 最近更新.
  Future<PagedResult> fetchHome() async {
    try {
      final html = await _getPage('/index.php');
      final items = P91Parser.parseList(html);
      if (items.isNotEmpty) {
        return PagedResult(items: items, page: 1, totalPage: 1);
      }
    } catch (_) {/* fall through */}
    return fetchCategory('rf', 1);
  }

  Future<PagedResult> search(String keyword, int page) async {
    if (keyword.trim().isEmpty) return PagedResult.empty;
    final kw = Uri.encodeComponent(keyword.trim());
    final html = await _getPage(
        '/search_result.php?search_id=$kw&search_type=search_videos&viewtype=basic&page=$page');
    return _toPaged(html, page);
  }

  Future<VideoItem> fetchDetail(String viewKey) async {
    final html = await _getPage('/view_video.php?viewkey=$viewKey');
    return P91Parser.parseDetail(html, viewKey);
  }

  /// Resolve a signed, directly playable URL — with the daily-10 bypass loop.
  /// The signature is one-shot, so this is always called fresh at play time.
  Future<ResolvedSource> resolveSource(String viewKey) async {
    final attempts = _bypassEnabled ? _maxAttempts : 1;
    final hosts = _candidateHosts();
    final logs = <String>[];

    for (var i = 0; i < attempts; i++) {
      final targetHost = hosts[i % hosts.length];
      final fp = _rotator.next();
      try {
        final html = await _getPage(
          '/view_video.php?viewkey=$viewKey',
          fp: fp,
          host: targetHost,
        );
        if (_isQuota(html)) {
          logs.add('#${i + 1} 限额 host=${_short(targetHost)} '
              'proxy=${fp.proxy ?? "直连"}');
          continue;
        }
        final url = P91Parser.resolveVideoUrl(html);
        if (url != null && url.isNotEmpty) {
          logs.add('#${i + 1} 成功 host=${_short(targetHost)} '
              'proxy=${fp.proxy ?? "直连"}');
          _lastAttemptLog = logs.join('\n');
          return ResolvedSource(
            url: url,
            name: '91 直链',
            videoId: _variantId(url),
            headers: mediaHeaders(targetHost),
          );
        }
        logs.add('#${i + 1} 无源 host=${_short(targetHost)}');
      } catch (e) {
        logs.add('#${i + 1} 异常 host=${_short(targetHost)}: $e');
      }
      if (i < attempts - 1) {
        await Future<void>.delayed(
          Duration(milliseconds: 120 + _rand.nextInt(260)),
        );
      }
    }

    _lastAttemptLog = logs.join('\n');
    throw P91Exception(
      '解析失败：$attempts 次尝试未取得可用直链。'
      '若均显示「限额」，说明源站不再信任伪造 IP，'
      '请在「设置 → 反限额」填入可用代理池后重试。',
    );
  }

  Future<ResolvedSource> resolveFromPageUrl(String pageUrl) async {
    final vk = RegExp(r'viewkey=([a-z0-9]+)', caseSensitive: false)
        .firstMatch(pageUrl)
        ?.group(1);
    if (vk != null) return resolveSource(vk);
    final html = await _getPage(_relative(pageUrl));
    final url = P91Parser.resolveVideoUrl(html);
    if (url == null) throw P91Exception('解析失败');
    return ResolvedSource(
      url: url,
      name: '91 直链',
      headers: mediaHeaders(),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<String> _candidateHosts() {
    final set = <String>{_host};
    for (final h in ApiConstants.altHosts) {
      set.add(_norm(h));
    }
    set.addAll(_extraHosts);
    return set.where((e) => e.isNotEmpty).toList();
  }

  bool _isQuota(String html) => ApiConstants.quotaMarkers.any(html.contains);

  String _short(String host) => host.replaceFirst(RegExp(r'^https?://'), '');

  PagedResult _toPaged(String html, int page) {
    final items = P91Parser.parseList(html);
    final total = P91Parser.parseTotalPage(html) ?? (items.isEmpty ? page : page + 1);
    return PagedResult(items: items, page: page, totalPage: total);
  }

  String _relative(String url) {
    if (url.startsWith('http')) {
      final idx = url.indexOf('/', url.indexOf('//') + 2);
      return idx >= 0 ? url.substring(idx) : '/';
    }
    return url.startsWith('/') ? url : '/$url';
  }

  String? _variantId(String url) {
    final m = RegExp(r'/([^/]+)\.mp4', caseSensitive: false).firstMatch(url);
    return m?.group(1);
  }
}

class P91Exception implements Exception {
  P91Exception(this.message);
  final String message;

  @override
  String toString() => message;
}
