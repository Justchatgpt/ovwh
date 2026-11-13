/// Global constants for the 91 source contract.
///
/// Everything here is derived from reverse-engineering the three original
/// 91 implementations found in `1on/`:
///  - `9orn1`  (iOS, Objective-C)  -> ApiService.m / ParseTool.m
///  - `9orn2`  (Android, Java)     -> ParseUtils.java / MyApplication.java
///  - `p91-rex-widget` (TS widget) -> src/index.ts
class ApiConstants {
  ApiConstants._();

  /// Canonical entry. Real deployments rotate mirrors; the player lets the
  /// user override this in Settings (see [altHosts]).
  static const String defaultHost = 'https://91porn.com';

  /// Known mirror patterns. The Android build hard-coded a rotating address
  /// (`91.91p18.space`), the newer widget keeps `91porn.com`. We expose a
  /// switchable host so the same scraping logic survives domain churn.
  static const List<String> altHosts = <String>[
    'https://91porn.com',
    'https://91.91p18.space',
    'https://91porn.work',
  ];

  /// Desktop UA is mandatory: the mobile page only serves ad placeholders,
  /// not the real `strencode2` stream (documented in p91 index.ts line 8).
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  /// `level=7` is required for the desktop page to emit the real source.
  static const String cookie = 'language=cn_CN; level=7';

  /// Ad / placeholder CDNs to never treat as a real stream (index.ts line 205).
  static const List<String> adHosts = <String>[
    '91p52.com',
    'kwai.net',
    'cdn77.org',
  ];

  /// Category codes accepted by `v.php?category=`. Mirrors:
  ///  - Android ApiService.m line 124 (`hot, rp, long, md, tf, mf, rf, top, top1, hd`)
  ///  - Widget enumOptions (`rf, hot, top, mf, md, long, longer, hd, ori`)
  static const Map<String, String> categories = <String, String>{
    'rf': '最近更新',
    'hot': '本月最热',
    'top': '本周最热',
    'mf': '收藏最多',
    'md': '评论最多',
    'long': '10分钟以上',
    'longer': '20分钟以上',
    'hd': '高清',
    'ori': '原创',
    'rp': '最近回复',
    'tf': '本月精华',
    'top1': '上月最热',
  };

  /// The site's daily free-view quota message. When present in the HTML the
  /// current IP has been throttled and we should rotate `X-Forwarded-For`.
  static const String quotaMarker = '你每天只可观看10个视频';

  /// Broader quota markers across 91 mirror variants / languages.
  static const List<String> quotaMarkers = <String>[
    '你每天只可观看10个视频',
    '每天只可观看',
    '只可观看10个',
    '观看上限',
    '10个视频的限',
    '10 videos per day',
    'daily limit',
    'exceeded the limit',
  ];

  /// Desktop UA pool — rotating this evades fixed-UA blocking AND spreads the
  /// "guest" fingerprint. Taken from Kazumi `constants.dart:userAgentsList`
  /// (also mirrored in Kazumi-Swift `HTTPHeaders.userAgents`).
  static const List<String> userAgents = <String>[
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36 Edg/141.0.0.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36 Edg/134.0.0.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36 Edg/136.0.0.0',
    userAgent,
  ];

  static const List<String> acceptLanguages = <String>[
    'zh-CN,zh;q=0.9',
    'zh-CN,zh;q=0.9,en;q=0.8,en-GB;q=0.7,en-US;q=0.6',
    'zh-CN,zh-TW;q=0.9,zh;q=0.8,en-US;q=0.7,en;q=0.6',
  ];

  /// Client-IP carry headers. Different mirrors / reverse proxies (Cloudflare,
  /// nginx realip, etc.) trust different ones, so we spoof the whole set per
  /// attempt — that is the core of the daily-10 bypass.
  static const List<String> clientIpHeaders = <String>[
    'X-Forwarded-For',
    'X-Real-IP',
    'CF-Connecting-IP',
    'True-Client-IP',
    'Client-IP',
    'X-Client-IP',
    'Forwarded',
  ];
}

