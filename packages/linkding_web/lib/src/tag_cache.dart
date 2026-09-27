import 'dart:convert';
import 'dart:js_interop';

import 'package:linkding_shared/linkding_shared.dart';
import 'package:web/web.dart' as web;

import 'api.dart';
import 'dom.dart';

/// The user's tags, loaded once and sorted by name, until a form is
/// submitted: linkding's `TagCache`.
final class TagCache {
  TagCache(this.api) {
    Listener(web.document, 'turbo:submit-end', (_) => _tags = null);
  }

  final Api api;
  Future<List<Tag>>? _tags;

  Future<List<Tag>> getTags() => _tags ??= api
      .getTags(limit: 5000)
      .then(
        (tags) => tags
          ..sort(
            (a, b) => localeCompare(a.name.toLowerCase(), b.name.toLowerCase()),
          ),
      )
      .catchError((Object e) {
        web.console.warn('Cache: Error loading tags $e'.toJS);
        return <Tag>[];
      });
}

final tagCache = TagCache(api);

/// Recent searches in `localStorage`: linkding's `SearchHistory`.
final class SearchHistory {
  static const _key = 'searchHistory';
  static const _maxEntries = 30;

  List<String> _recent() {
    final json = web.window.localStorage.getItem(_key);
    if (json == null) return [];
    final history = jsonDecode(json) as Map<String, Object?>;
    return [for (final entry in history['recent'] as List) entry as String];
  }

  /// Remembers the search of the page being shown.
  void pushCurrent() {
    final search = web.URLSearchParams(web.window.location.search.toJS)
        .get('q');
    if (search == null || search.isEmpty) return;
    push(search);
  }

  void push(String search) {
    final recent = <String>[];
    for (final entry in [search, ..._recent()]) {
      if (recent.length >= _maxEntries) break;
      if (!recent.contains(entry)) recent.add(entry);
    }
    web.window.localStorage.setItem(_key, jsonEncode({'recent': recent}));
  }

  List<String> recentSearches(String query, int max) => _recent()
      .where(
        (search) =>
            query.isEmpty || search.toLowerCase().contains(query.toLowerCase()),
      )
      .take(max)
      .toList();
}
