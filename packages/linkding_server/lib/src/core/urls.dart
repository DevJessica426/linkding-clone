import '../compat/pyurl.dart';

/// linkding's `normalize_url`: how it decides that two URLs are the same
/// bookmark.
///
/// Scheme and host are lower-cased, a trailing `/` is dropped, query
/// parameters are sorted, and user, port, params and fragment are kept. A URL
/// Python cannot split comes back trimmed but otherwise unchanged.
String normalizeUrl(String? url) {
  if (url == null) return '';
  url = url.trim();
  if (url.isEmpty) return '';
  try {
    final parsed = urlparse(url);
    final scheme = parsed.scheme.toLowerCase();
    var netloc = parsed.hostname?.toLowerCase() ?? '';
    final port = parsed.port;
    if (port != null && port != 0) netloc += ':$port';
    final username = parsed.username;
    if (username != null && username.isNotEmpty) {
      var auth = username;
      final password = parsed.password;
      if (password != null && password.isNotEmpty) auth += ':$password';
      netloc = '$auth@$netloc';
    }
    final path = parsed.path.replaceFirst(RegExp(r'/+$'), '');
    var query = '';
    if (parsed.query.isNotEmpty) {
      final pairs = parseQsl(parsed.query, keepBlankValues: true)
        ..sort((a, b) {
          final byKey = a.$1.compareTo(b.$1);
          return byKey != 0 ? byKey : a.$2.compareTo(b.$2);
        });
      query = urlencode(pairs, quoteVia: quote);
    }
    return urlunparse(
      scheme,
      netloc,
      path,
      parsed.params,
      query,
      parsed.fragment,
    );
  } on PyValueError {
    return url;
  }
}

/// A link to the Internet Archive's copy of [url] nearest to [timestamp],
/// which linkding offers when it stored no snapshot of its own.
String webArchiveFallbackUrl(String url, DateTime timestamp) {
  final t = timestamp.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final stamp =
      '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
      '${two(t.hour)}${two(t.minute)}${two(t.second)}';
  return 'https://web.archive.org/web/$stamp/$url';
}
