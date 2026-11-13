import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../core/constants.dart';
import '../models/video_item.dart';

/// Pure, side-effect-free HTML parsing for the 91 site.
///
/// Ported from:
///  - `9orn1/.../ParseTool.m`  (parseIndex / parseVideo / parseRecentUpate / parseVideoUrl)
///  - `9orn2/.../ParseUtils.java` (parseIndex / parseHot / parseVideoPlayUrl)
///  - `p91-rex-widget/src/index.ts` (parseCards / extractSource)
///
/// The site ships two lineage of the "encrypted source" trick:
///   legacy : document.write(strencode("<b64>","<key>","..."));  -> base64 XOR base64
///   current: strencode2("<url-encoded <source ...>>")           -> plain URL-decode
/// Both are handled, with a final heuristic mp4 scan as a safety net.
class P91Parser {
  P91Parser._();

  static final RegExp _viewKeyRe = RegExp(r'viewkey=([a-z0-9]+)', caseSensitive: false);
  static final RegExp _strencode2Re = RegExp(r'strencode2\(\s*"([^"]+)"\s*\)');
  static final RegExp _strencodeRe =
      RegExp(r'document\.write\(strencode\("(.+?)"\s*,\s*"(.+?)"\s*,\s*"[^"]*"\)\);');
  static final RegExp _srcRe = RegExp(r'''src=["']([^"']+)["']''', caseSensitive: false);
  static final RegExp _mp4Re =
      RegExp(r'''https?://[^"'\s<>]+\.(?:mp4|m3u8)[^"'\s<>]*''', caseSensitive: false);

  // ---------------------------------------------------------------------------
  // List parsing
  // ---------------------------------------------------------------------------

  /// Parse a list page. Handles the modern card layout and the legacy
  /// `#fullside .listchannel` layout. Returns [] when the page has no cards.
  static List<VideoItem> parseList(String html) {
    final doc = html_parser.parse(html);
    final modern = _parseModernCards(doc);
    if (modern.isNotEmpty) return modern;
    final legacy = _parseLegacyList(doc);
    if (legacy.isNotEmpty) return legacy;
    return _parseCardRegExp(html);
  }

  static List<VideoItem> _parseModernCards(dom.Document doc) {
    final out = <VideoItem>[];
    final cards = doc.querySelectorAll('.videos-text-align');
    for (final card in cards) {
      final link = _firstAnchor(card, 'viewkey=');
      if (link == null) continue;
      final href = link.attributes['href'] ?? '';
      final vk = _viewKeyRe.firstMatch(href)?.group(1);
      if (vk == null) continue;

      final img = card.querySelector('img');
      final cover = img?.attributes['src'] ?? '';
      final durEl = card.querySelector('.duration');
      final duration = durEl?.text.trim() ?? '';
      final titleEl = card.querySelector('.video-title');
      String title = titleEl?.text.trim() ?? '';
      if (title.isEmpty) title = img?.attributes['title']?.trim() ?? '';
      if (title.isEmpty) title = '视频 $vk';

      String info = '';
      final cardText = card.text;
      final idx = cardText.indexOf('添加时间');
      if (idx >= 0) {
        info = _squash(cardText.substring(idx));
      } else {
        final fromEl = card.querySelector('.info');
        if (fromEl != null && fromEl.text.contains('From:')) {
          info = _squash(fromEl.text);
        }
      }

      out.add(VideoItem(
        viewKey: vk,
        title: cleanTitle(title),
        cover: cover,
        duration: duration,
        durationSeconds: durationToSeconds(duration),
        info: info,
        pageUrl: '${ApiConstants.defaultHost}/view_video.php?viewkey=$vk',
      ));
    }
    return out;
  }

  static List<VideoItem> _parseLegacyList(dom.Document doc) {
    final out = <VideoItem>[];
    final body = doc.querySelector('#fullside');
    if (body == null) return out;
    for (final el in body.querySelectorAll('.listchannel')) {
      final a = el.querySelector('a');
      if (a == null) continue;
      var href = a.attributes['href'] ?? '';
      final amp = href.indexOf('&');
      if (amp >= 0) href = href.substring(0, amp);
      final vk = href.substring(href.lastIndexOf('=') + 1);
      final img = a.querySelector('img');
      final cover = img?.attributes['src'] ?? '';
      final title = (img?.attributes['title'] ?? '视频 $vk').trim();
      final text = el.text;
      final dur = _sliceAround(text, ['时长', 'Runtime'], 5);
      final infoIdx = _firstIndex(text, ['添加时间', 'Added']);
      final info = infoIdx >= 0 ? _squash(text.substring(infoIdx)) : '';
      if (vk.isEmpty) continue;
      out.add(VideoItem(
        viewKey: vk,
        title: cleanTitle(title),
        cover: cover,
        duration: dur,
        durationSeconds: durationToSeconds(dur),
        info: info,
        pageUrl: '${ApiConstants.defaultHost}/view_video.php?viewkey=$vk',
      ));
    }
    return out;
  }

  /// Last-resort regex based card parser (mirrors p91 index.ts CARD_RE).
  static List<VideoItem> _parseCardRegExp(String html) {
    final out = <VideoItem>[];
    final cardRe = RegExp(
        r'<div class="well well-sm videos-text-align">([\s\S]*?)<\/div>\s*<\/div>');
    final titleRe = RegExp(r'<span class="video-title[^"]*">([\s\S]*?)</span>');
    final thumbRe = RegExp(r'<img[^>]+src="([^"]+)"');
    final durRe = RegExp(r'<span class="duration">\s*([\d:]+)\s*</span>');
    for (final m in cardRe.allMatches(html)) {
      final block = m.group(1)!;
      final vk = _viewKeyRe.firstMatch(block)?.group(1);
      if (vk == null) continue;
      final title = cleanTitle(_stripTags(titleRe.firstMatch(block)?.group(1) ?? '') ?? '');
      final cover = thumbRe.firstMatch(block)?.group(1) ?? '';
      final dur = durRe.firstMatch(block)?.group(1) ?? '';
      out.add(VideoItem(
        viewKey: vk,
        title: title.isEmpty ? '视频 $vk' : title,
        cover: cover,
        duration: dur,
        durationSeconds: durationToSeconds(dur),
        pageUrl: '${ApiConstants.defaultHost}/view_video.php?viewkey=$vk',
      ));
    }
    return out;
  }

  /// Try to read the total page count from a list page's pagination block.
  /// Returns null when unknown.
  static int? parseTotalPage(String html) {
    final doc = html_parser.parse(html);
    final candidates = <int>[];
    for (final sel in ['#paging a', '.pagination a', '.pager a']) {
      for (final a in doc.querySelectorAll(sel)) {
        final n = int.tryParse(a.text.trim());
        if (n != null) candidates.add(n);
      }
    }
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) => a > b ? a : b);
  }

  // ---------------------------------------------------------------------------
  // Detail parsing
  // ---------------------------------------------------------------------------

  /// Parse title / cover / owner from a detail page.
  static VideoItem parseDetail(String html, String viewKey) {
    final doc = html_parser.parse(html);

    String title = '';
    final titleEl = doc.querySelector('#viewvideo-title');
    if (titleEl != null) title = titleEl.text.replaceAll('\n', '').trim();
    if (title.isEmpty) {
      title = _stripTags(RegExp(r'<title>([\s\S]*?)</title>', caseSensitive: false)
              .firstMatch(html)
              ?.group(1) ??
          '');
    }

    String cover = '';
    final vid = doc.querySelector('#vid');
    if (vid != null) cover = vid.attributes['poster'] ?? '';
    if (cover.isEmpty) {
      final og = RegExp(r'''og:image["'][^>]+content=["']([^"']+)''', caseSensitive: false)
          .firstMatch(html);
      cover = og?.group(1) ?? '';
    }

    String ownerName = '';
    String ownerId = '';
    final ownerA = _firstAnchor(doc.body, 'UID');
    if (ownerA != null) {
      ownerName = ownerA.text.trim();
      final href = ownerA.attributes['href'] ?? '';
      final eq = href.indexOf('=');
      if (eq >= 0) ownerId = href.substring(eq + 1);
    }

    final infoParts = <String>[];
    if (ownerName.isNotEmpty) infoParts.add('作者: $ownerName');

    return VideoItem(
      viewKey: viewKey,
      title: cleanTitle(title),
      cover: cover,
      ownerName: ownerName,
      info: infoParts.join('  '),
      pageUrl: '${ApiConstants.defaultHost}/view_video.php?viewkey=$viewKey',
    );
  }

  // ---------------------------------------------------------------------------
  // Stream URL extraction
  // ---------------------------------------------------------------------------

  /// Return a directly playable URL, or null if the page is throttled / empty.
  static String? resolveVideoUrl(String html) {
    // 1) modern: strencode2("<url-encoded source tag>")
    final m2 = _strencode2Re.firstMatch(html);
    if (m2 != null) {
      try {
        final dec = Uri.decodeComponent(m2.group(1)!);
        final s = _srcRe.firstMatch(dec);
        if (s != null && _isHttp(s.group(1)!)) return _cleanUrl(s.group(1)!);
        final s2 = _mp4Re.firstMatch(dec);
        if (s2 != null) return _cleanUrl(s2.group(0)!);
      } catch (_) {/* fall through */}
    }

    // 2) legacy: document.write(strencode("<b64>","<key>","..."));
    final m1 = _strencodeRe.firstMatch(html);
    if (m1 != null) {
      try {
        final decoded = decodeStrencode(m1.group(1)!, m1.group(2)!);
        final s = _srcRe.firstMatch(decoded) ?? _mp4Re.firstMatch(decoded);
        if (s != null) return _cleanUrl(s.group(0)!.startsWith('http') ? s.group(0)! : s.group(1)!);
      } catch (_) {/* fall through */}
    }

    // 3) heuristic scan of every .mp4, skipping known ad hosts.
    final all = _mp4Re.allMatches(html).map((m) => m.group(0)!).toList();
    for (final u in all) {
      if (_isAd(u)) continue;
      if (u.contains('st=') || u.contains('mp43/')) return _cleanUrl(u);
    }
    for (final u in all) {
      if (!_isAd(u)) return _cleanUrl(u);
    }

    // 4) bare <source>/<video src> (mp4 or HLS m3u8)
    final ms = RegExp(r'''<(?:source|video)[^>]+src=["']([^"']+\.(?:mp4|m3u8)[^"']*)["']''',
            caseSensitive: false)
        .firstMatch(html);
    if (ms != null) return _cleanUrl(_decodeEntities(ms.group(1)!));
    return null;
  }

  /// Decode the legacy `strencode(b64, key, ...)` blob.
  /// base64.decode(b64) XOR keyBytes -> ASCII base64 -> base64.decode -> HTML.
  static String decodeStrencode(String b64, String key) {
    final data = base64.decode(_normalizeBase64(b64));
    final k = utf8.encode(key);
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = data[i] ^ k[i % k.length];
    }
    final inner = String.fromCharCodes(out);
    final sourceHtml = utf8.decode(base64.decode(_normalizeBase64(inner)), allowMalformed: true);
    return sourceHtml;
  }

  // ---------------------------------------------------------------------------
  // Small helpers
  // ---------------------------------------------------------------------------

  static String _normalizeBase64(String s) {
    var t = s.replaceAll(RegExp(r'[^A-Za-z0-9+/=]'), '');
    // url-safe -> std
    t = t.replaceAll('-', '+').replaceAll('_', '/');
    final mod = t.length % 4;
    if (mod == 2) {
      t += '==';
    } else if (mod == 3) {
      t += '=';
    } else if (mod == 1) {
      t = t.substring(0, t.length - 1);
    }
    return t;
  }

  static bool _isHttp(String url) => url.startsWith('http://') || url.startsWith('https://');

  static bool _isAd(String url) => ApiConstants.adHosts.any(url.contains);

  static String _cleanUrl(String url) =>
      _decodeEntities(url).replaceAll('&amp;', '&').trim();

  static String _decodeEntities(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ');

  static String _stripTags(String s) => s.replaceAll(RegExp(r'<[^>]*>'), '');

  /// Find the first `<a>` under [root] whose href contains [needle].
  static dom.Element? _firstAnchor(dom.Element? root, String needle) {
    if (root == null) return null;
    for (final a in root.querySelectorAll('a')) {
      final href = a.attributes['href'] ?? '';
      if (href.contains(needle)) return a;
    }
    return null;
  }

  static String _squash(String s) => s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();

  static int _firstIndex(String text, List<String> needles) {
    for (final n in needles) {
      final i = text.indexOf(n);
      if (i >= 0) return i;
    }
    return -1;
  }

  static String _sliceAround(String text, List<String> marks, int len) {
    for (final m in marks) {
      final i = text.indexOf(m);
      if (i >= 0) {
        final start = i + m.length;
        final end = (start + len).clamp(0, text.length) as int;
        return text.substring(start, end).trim();
      }
    }
    return '';
  }

  static String cleanTitle(String raw) {
    var t = _decodeEntities(_stripTags(raw)).trim();
    t = t.replaceAll(RegExp(r'\s*-\s*91porn\s*$', caseSensitive: false), '');
    return t.trim();
  }

  static int durationToSeconds(String t) {
    if (t.isEmpty) return 0;
    final parts = t.split(':').map((x) => int.tryParse(x.trim()) ?? 0).toList();
    while (parts.length < 3) {
      parts.insert(0, 0);
    }
    return parts[0] * 3600 + parts[1] * 60 + parts[2];
  }
}
