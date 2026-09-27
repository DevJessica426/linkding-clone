/// Writing HTML safely: every value from a user goes through [e] (text and
/// attribute values) or [q] (a query-string value) before it reaches markup.
library;

import 'dart:math';

import '../compat/pyurl.dart';

/// Django's `escape`: `&`, `<`, `>`, `"` and `'`.
String e(Object? value) {
  final text = value?.toString() ?? '';
  if (!text.contains(RegExp('[&<>"\']'))) return text;
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#x27;');
}

/// Django's `urlencode` filter: percent-encoding with `/` kept.
String q(Object? value) => quote(value?.toString() ?? '');

/// A query string from [params], skipping null values, as `?a=1&b=2`, or
/// the empty string when there are none.
String queryString(Map<String, Object?> params) {
  final pairs = [
    for (final MapEntry(:key, :value) in params.entries)
      if (value != null) (key, '$value'),
  ];
  return pairs.isEmpty ? '' : '?${urlencode(pairs)}';
}

const _csrfChars =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// Django's per-page masking of the CSRF secret, so the token in the page
/// differs from the cookie while still proving it.
String maskCsrf(String secret) {
  final random = Random.secure();
  final mask = String.fromCharCodes([
    for (var i = 0; i < 32; i++)
      _csrfChars.codeUnitAt(random.nextInt(_csrfChars.length)),
  ]);
  final out = StringBuffer(mask);
  for (var i = 0; i < 32; i++) {
    final s = _csrfChars.indexOf(secret[i]);
    final m = _csrfChars.indexOf(mask[i]);
    out.write(_csrfChars[(s + m) % _csrfChars.length]);
  }
  return out.toString();
}
