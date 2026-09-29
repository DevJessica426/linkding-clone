/// Writing HTML safely: every value from a user goes through [e] (text and
/// attribute values) or [q] (a query-string value) before it reaches markup.
library;

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
