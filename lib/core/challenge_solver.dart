import 'package:flutter/services.dart';

/// Result of a WKWebView challenge run.
class ChallengeResult {
  const ChallengeResult({required this.html, required this.cookies, this.finalUrl = ''});
  final String html;
  final Map<String, String> cookies;
  final String finalUrl;
}

/// Bridges to the native `p91/challenge` WKWebView runner (AppDelegate.swift).
///
/// Some 91 mirror mirrors sit behind an anti-bot interstitial that renders a
/// "Redirecting…" page and then does `document.write(<random link>).click()`
/// after checking `navigator.webdriver`, GPU, timezone, adblock presence, etc.
/// A plain HTTP client (Dio) receives that tiny JS page and cannot proceed.
/// WKWebView executes the JS naturally, passes the check, follows the redirect,
/// and we then read the final DOM (which contains the real list/detail page,
/// including the `strencode2(...)` payload) plus the cookies it set.
class ChallengeSolver {
  ChallengeSolver._();

  static const MethodChannel _channel = MethodChannel('p91/challenge');

  /// Heuristic: is this HTML an anti-bot / verification interstitial rather
  /// than the real page?
  static bool looksLikeChallenge(String html) {
    if (html.length > 60000) return false; // real pages are much bigger
    final l = html.toLowerCase();
    // Cloudflare managed challenge.
    if (l.contains('cf-chl') ||
        l.contains('just a moment') ||
        l.contains('/cdn-cgi/challenge-platform') ||
        l.contains('checking your browser')) {
      return true;
    }
    // The custom "Redirecting…" gate seen on 91 clone mirrors.
    if (l.contains('redirecting') &&
        (l.contains('adblockingdetected') ||
            l.contains('prebid-wrapper') ||
            l.contains('document.write') ||
            l.contains('adblock'))) {
      return true;
    }
    return false;
  }

  /// Run the URL through the native hidden WKWebView. Returns null when the
  /// platform channel is unavailable (e.g. Android/web) or the run failed.
  static Future<ChallengeResult?> solve({
    required String url,
    Map<String, String> headers = const <String, String>{},
    int timeoutMs = 25000,
  }) async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('solveChallenge', {
        'url': url,
        'headers': headers,
        'timeoutMs': timeoutMs,
      });
      if (raw is! Map) return null;
      final html = (raw['html'] as String?) ?? '';
      final cookies = <String, String>{};
      final c = raw['cookies'];
      if (c is Map) {
        c.forEach((k, v) => cookies['$k'] = '$v');
      }
      return ChallengeResult(
        html: html,
        cookies: cookies,
        finalUrl: (raw['finalUrl'] as String?) ?? '',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
