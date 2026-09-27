import '../compat/idna.dart';
import '../compat/pyurl.dart';

/// Thrown where linkding's `auto_tagging.get_tags` raises. Callers treat it
/// as "no automatic tags", as linkding's do.
final class AutoTaggingError implements Exception {
  const AutoTaggingError(this.cause);
  final Object cause;
  @override
  String toString() => 'AutoTaggingError: $cause';
}

/// The tags [rules] add to a bookmark for [url].
///
/// Each non-comment line is a URL pattern followed by tags. The pattern's
/// domain must end the bookmark's domain (after IDNA encoding), and its path,
/// query parameters and fragment, where given, must match too. Everything is
/// compared in lower case. One malformed rule makes the whole call fail, as
/// in linkding: the result is then no automatic tags at all.
Set<String> autoTags(String rules, String url) {
  try {
    return _autoTags(rules, url);
  } on AutoTaggingError {
    rethrow;
  } on Object catch (error) {
    throw AutoTaggingError(error);
  }
}

Set<String> _autoTags(String rules, String url) {
  final parsedUrl = urlparse(url.toLowerCase());
  final result = <String>{};
  final host = parsedUrl.hostname;
  if (host == null) return result;

  for (var line in rules.toLowerCase().split('\n')) {
    line = line.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final comment = RegExp(r'\s+#').firstMatch(line);
    if (comment != null) line = line.substring(0, comment.start);
    final parts = line
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.length < 2) continue;

    final pattern = urlparse(
      '//${parts.first.replaceFirst(RegExp(r'^https?://'), '')}',
    );
    final patternHost = pattern.hostname;
    if (patternHost == null) {
      // Python passes None to idna.encode, which raises.
      throw const AutoTaggingError('rule without a host');
    }
    if (!idnaEncode(host).endsWith(idnaEncode(patternHost))) continue;
    if (pattern.path.isNotEmpty && !parsedUrl.path.startsWith(pattern.path)) {
      continue;
    }
    if (pattern.query.isNotEmpty &&
        !_queryMatches(pattern.query, parsedUrl.query)) {
      continue;
    }
    if (pattern.fragment.isNotEmpty &&
        !parsedUrl.fragment.startsWith(pattern.fragment)) {
      continue;
    }
    result.addAll(parts.skip(1));
  }
  return result;
}

bool _queryMatches(String expected, String actual) {
  final want = parseQs(expected, keepBlankValues: true);
  final have = parseQs(actual, keepBlankValues: true);
  for (final entry in want.entries) {
    final values = have[entry.key];
    if (values == null) return false;
    for (final value in entry.value) {
      if (value.isNotEmpty && !values.contains(value)) return false;
    }
  }
  return true;
}
