import '../compat/pyurl.dart';

/// DRF's `replace_query_param`: [url] with [key] set to [value] and the
/// query re-encoded in key order.
String replaceQueryParam(String url, String key, String value) {
  final split = urlsplit(url);
  final query = parseQs(split.query, keepBlankValues: true)..[key] = [value];
  return urlunsplit(
    split.scheme,
    split.netloc,
    split.path,
    _encodeSorted(query),
    split.fragment,
  );
}

/// DRF's `remove_query_param`.
String removeQueryParam(String url, String key) {
  final split = urlsplit(url);
  final query = parseQs(split.query, keepBlankValues: true)..remove(key);
  return urlunsplit(
    split.scheme,
    split.netloc,
    split.path,
    _encodeSorted(query),
    split.fragment,
  );
}

String _encodeSorted(Map<String, List<String>> query) {
  final keys = query.keys.toList()..sort();
  return urlencode([
    for (final key in keys)
      for (final value in query[key]!) (key, value),
  ]);
}

/// DRF's `LimitOffsetPagination` with linkding's page size of 100.
final class LimitOffset {
  const LimitOffset(this.limit, this.offset);

  /// Reads `limit` and `offset` as DRF does: a limit that is missing, not a
  /// number or not positive becomes 100; an offset that is missing, not a
  /// number or negative becomes 0.
  factory LimitOffset.fromQuery(Map<String, String> query) {
    var limit = defaultLimit;
    final rawLimit = _pythonInt(query['limit']);
    if (rawLimit != null && rawLimit > 0) limit = rawLimit;
    var offset = 0;
    final rawOffset = _pythonInt(query['offset']);
    if (rawOffset != null && rawOffset >= 0) offset = rawOffset;
    return LimitOffset(limit, offset);
  }

  static const defaultLimit = 100;

  final int limit;
  final int offset;

  /// The next page's absolute URL, from the request's own [url].
  String? next(String url, int count) {
    if (offset + limit >= count) return null;
    return replaceQueryParam(
      replaceQueryParam(url, 'limit', '$limit'),
      'offset',
      '${offset + limit}',
    );
  }

  /// The previous page's absolute URL.
  String? previous(String url) {
    if (offset <= 0) return null;
    final withLimit = replaceQueryParam(url, 'limit', '$limit');
    if (offset - limit <= 0) return removeQueryParam(withLimit, 'offset');
    return replaceQueryParam(withLimit, 'offset', '${offset - limit}');
  }
}

/// Python's `int(str)`: surrounding whitespace and `_` between digits
/// allowed, a sign allowed.
int? _pythonInt(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (!RegExp(r'^[+-]?\d+(?:_\d+)*$').hasMatch(trimmed)) return null;
  return int.tryParse(trimmed.replaceAll('_', ''));
}
