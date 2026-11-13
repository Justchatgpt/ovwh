/// A parsed proxy endpoint used for real-IP rotation.
///
/// Only HTTP proxies are supported for the request layer (Dart `HttpClient`
/// `findProxy` speaks `PROXY host:port`). SOCKS5 can be added later via a
/// dedicated adapter; note it in the proxy text and it is skipped.
class ProxyEntry {
  const ProxyEntry(this.host, this.port);
  final String host;
  final int port;

  String get address => '$host:$port';

  @override
  String toString() => address;
}

class ProxyPool {
  ProxyPool(this.entries);

  final List<ProxyEntry> entries;

  bool get isEmpty => entries.isEmpty;
  int get length => entries.length;

  ProxyEntry? at(int index) =>
      entries.isEmpty ? null : entries[index % entries.length];

  /// Parse a multi-line proxy list. Accepts `host:port`, optionally prefixed
  /// with `http://` / `https://`. Blank lines and `#` comments are ignored.
  /// `socks5://` / `socks4://` lines are skipped (not supported by findProxy).
  static ProxyPool parse(String raw) {
    final out = <ProxyEntry>[];
    for (final line in raw.split(RegExp(r'[\r\n,;]+'))) {
      var s = line.trim();
      if (s.isEmpty || s.startsWith('#')) continue;
      final lower = s.toLowerCase();
      if (lower.startsWith('socks')) continue;
      for (final p in const ['http://', 'https://']) {
        if (lower.startsWith(p)) {
          s = s.substring(p.length);
          break;
        }
      }
      // strip any trailing path
      final slash = s.indexOf('/');
      if (slash >= 0) s = s.substring(0, slash);
      final idx = s.lastIndexOf(':');
      if (idx <= 0) continue;
      final host = s.substring(0, idx).trim();
      final port = int.tryParse(s.substring(idx + 1).trim());
      if (host.isEmpty || port == null || port <= 0 || port > 65535) continue;
      out.add(ProxyEntry(host, port));
    }
    return ProxyPool(out);
  }
}
