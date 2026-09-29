import '../../compat/pyurl.dart';

/// A request's query parameters in order, where a key can repeat: Django's
/// `QueryDict`, which linkding copies and edits to build every link on a
/// list page. Setting a key keeps its position; a new key goes last.
final class QueryParams {
  QueryParams._(this._entries);

  factory QueryParams.parse(String query) {
    final entries = <String, List<String>>{};
    for (final (key, value) in parseQsl(query, keepBlankValues: true)) {
      (entries[key] ??= []).add(value);
    }
    return QueryParams._(entries);
  }

  final Map<String, List<String>> _entries;

  QueryParams copy() => QueryParams._({
    for (final MapEntry(:key, :value) in _entries.entries) key: [...value],
  });

  /// The last value of [key], as `QueryDict.get` returns it.
  String? operator [](String key) => _entries[key]?.last;

  void operator []=(String key, String value) => _entries[key] = [value];

  /// Adds a value after any the key has: `QueryDict.update`.
  void add(String key, String value) => (_entries[key] ??= []).add(value);

  /// The last value of every key, as `QueryDict.items()` gives them.
  Map<String, String> get last => {
    for (final MapEntry(:key, :value) in _entries.entries) key: value.last,
  };

  void remove(String key) => _entries.remove(key);

  bool containsKey(String key) => _entries.containsKey(key);

  bool get isEmpty => _entries.isEmpty;

  /// `QueryDict.urlencode()`: `quote_plus` for keys and values.
  String encode() => urlencode([
    for (final MapEntry(:key, :value) in _entries.entries)
      for (final v in value) (key, v),
  ]);
}
