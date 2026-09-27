import 'package:dust_dart/db.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../compat/django.dart';
import '../core/profile.dart';
import '../db/bookmarks_repo.dart';
import '../db/bundles_repo.dart';
import '../db/rows.dart';
import 'errors.dart';

/// Which list a search runs over.
enum BookmarkList { active, archived, shared }

/// linkding's `BookmarkSearch`: the query, filters and sort of one list.
final class BookmarkSearch {
  const BookmarkSearch({
    this.q = '',
    this.user = '',
    this.bundle,
    this.sort = 'added_desc',
    this.shared = 'off',
    this.unread = 'off',
    this.modifiedSince,
    this.addedSince,
    this.defaults = const {
      'sort': 'added_desc',
      'shared': 'off',
      'unread': 'off',
    },
  });

  /// Reads the query string as `BookmarkSearch.from_request` does: empty
  /// values fall back to the defaults, and `bundle` is looked up among the
  /// owner's bundles; an unknown or malformed id means no bundle.
  static Future<BookmarkSearch> fromQuery(
    Executor db,
    Map<String, String> query, {
    int? ownerId,
    Map<String, String> preferences = const {},
  }) async {
    String? value(String key) {
      final v = query[key];
      return v == null || v.isEmpty ? null : v;
    }

    final defaults = {
      'sort': 'added_desc',
      'shared': 'off',
      'unread': 'off',
      ...preferences,
    };
    BundleRow? bundle;
    final bundleId = int.tryParse(value('bundle') ?? '');
    if (bundleId != null &&
        ownerId != null &&
        bundleId >= 0 &&
        bundleId <= 2147483647) {
      bundle = (await BundlesRepo(db).owned(bundleId, ownerId)).orThrow;
    }
    return BookmarkSearch(
      q: value('q') ?? '',
      user: value('user') ?? '',
      bundle: bundle,
      sort: value('sort') ?? defaults['sort']!,
      shared: value('shared') ?? defaults['shared']!,
      unread: value('unread') ?? defaults['unread']!,
      modifiedSince: value('modified_since'),
      addedSince: value('added_since'),
      defaults: defaults,
    );
  }

  final String q;
  final String user;
  final BundleRow? bundle;
  final String sort;
  final String shared;
  final String unread;
  final String? modifiedSince;
  final String? addedSince;

  /// The preferences in effect, to tell a changed value from a default.
  final Map<String, String> defaults;
}

/// A bookmark with its tag names, as the search sees it.
final class Candidate {
  const Candidate(this.row, this.tags);
  final BookmarkRow row;
  final List<String> tags;
}

/// Runs searches. The list, its filters and its order come from one fixed
/// query; the search expression and the bundle are then applied here, with
/// the same meaning linkding's database conditions have.
final class BookmarkSearchQuery {
  const BookmarkSearchQuery(this.db);

  final Executor db;

  /// Every match, in order, with its tag names.
  Future<List<Candidate>> run({
    required BookmarkList list,
    required BookmarkSearch search,
    required Profile? profile,
    int? ownerId,
    bool publicOnly = false,
  }) async {
    final repo = BookmarksRepo(db);
    final rows = (await repo.list(
      ownerId,
      list.name,
      publicOnly,
      parseSinceFilter(search.modifiedSince),
      parseSinceFilter(search.addedSince),
      search.unread,
      search.shared,
      search.sort,
    )).orThrow;

    final tagsById = <int, List<String>>{};
    if (rows.isNotEmpty) {
      final tagRows = (await repo.tagNames([for (final r in rows) r.id]))
          .orThrow;
      for (final tag in tagRows) {
        (tagsById[tag.bookmarkId] ??= []).add(tag.name);
      }
    }
    final candidates = [
      for (final row in rows) Candidate(row, tagsById[row.id] ?? const []),
    ];

    final filter = _Filter.of(search, profile);
    return [
      for (final candidate in candidates)
        if (filter.matches(candidate)) candidate,
    ];
  }
}

/// The search expression (or legacy query) and bundle of one search.
final class _Filter {
  _Filter(this.expression, this.legacy, this.bundle, this.lax, this.nothing);

  factory _Filter.of(BookmarkSearch search, Profile? profile) {
    final lax = profile?.laxTags ?? false;
    if (profile?.legacySearch ?? false) {
      return _Filter(
        null,
        LegacyQuery.parse(search.q),
        search.bundle,
        lax,
        false,
      );
    }
    try {
      return _Filter(
        parseSearchQuery(search.q),
        null,
        search.bundle,
        lax,
        false,
      );
    } on SearchQueryParseError {
      // linkding answers a query it cannot parse with no results.
      return _Filter(null, null, search.bundle, lax, true);
    }
  }

  final SearchExpression? expression;
  final LegacyQuery? legacy;
  final BundleRow? bundle;
  final bool lax;
  final bool nothing;

  bool matches(Candidate c) {
    if (nothing) return false;
    final expression = this.expression;
    if (expression != null && _evaluate(expression, c) == false) return false;
    final legacy = this.legacy;
    if (legacy != null && !_matchesLegacy(legacy, c)) return false;
    final bundle = this.bundle;
    if (bundle != null && !_matchesBundle(bundle, c)) return false;
    return true;
  }

  /// True, false, or null for Django's empty `Q()` — an unknown `!keyword` —
  /// which drops out of `and`/`or` rather than counting as true.
  bool? _evaluate(SearchExpression expression, Candidate c) {
    switch (expression) {
      case TermExpression(:final term):
        return _containsTerm(c, term) || (lax && _hasTag(c, term));
      case TagExpression(:final tag):
        return _hasTag(c, tag);
      case SpecialKeywordExpression(:final keyword):
        return switch (keyword.toLowerCase()) {
          'unread' => c.row.unread,
          'untagged' => c.tags.isEmpty,
          _ => null,
        };
      case AndExpression(:final left, :final right):
        final l = _evaluate(left, c);
        final r = _evaluate(right, c);
        if (l == null) return r;
        if (r == null) return l;
        return l && r;
      case OrExpression(:final left, :final right):
        final l = _evaluate(left, c);
        final r = _evaluate(right, c);
        if (l == null) return r;
        if (r == null) return l;
        return l || r;
      case NotExpression(:final operand):
        final value = _evaluate(operand, c);
        return value == null ? null : !value;
    }
  }

  bool _matchesLegacy(LegacyQuery query, Candidate c) =>
      query.searchTerms.every(
        (term) => _containsTerm(c, term) || (lax && _hasTag(c, term)),
      ) &&
      query.tagNames.every((tag) => _hasTag(c, tag)) &&
      (!query.untagged || c.tags.isEmpty) &&
      (!query.unread || c.row.unread);

  /// linkding's `_filter_bundle`.
  bool _matchesBundle(BundleRow bundle, Candidate c) {
    final terms = LegacyQuery.parse(bundle.search).searchTerms;
    if (!terms.every((term) => _containsTerm(c, term))) return false;
    final anyTags = parseTagString(bundle.anyTags, delimiter: ' ');
    if (anyTags.isNotEmpty && !anyTags.any((t) => _hasTag(c, t))) return false;
    final allTags = parseTagString(bundle.allTags, delimiter: ' ');
    if (!allTags.every((t) => _hasTag(c, t))) return false;
    final excluded = parseTagString(bundle.excludedTags, delimiter: ' ');
    if (excluded.any((t) => _hasTag(c, t))) return false;
    if (!_filterMatches(bundle.filterUnread, c.row.unread)) return false;
    return _filterMatches(bundle.filterShared, c.row.shared);
  }
}

bool _filterMatches(String filter, bool value) => switch (filter) {
  'yes' => value,
  'no' => !value,
  _ => true,
};

/// Django's `icontains` on PostgreSQL compares `UPPER()` of both sides.
bool _containsTerm(Candidate c, String term) {
  final needle = term.toUpperCase();
  final row = c.row;
  return row.title.toUpperCase().contains(needle) ||
      row.description.toUpperCase().contains(needle) ||
      row.notes.toUpperCase().contains(needle) ||
      row.url.toUpperCase().contains(needle);
}

/// Django's `iexact` on tag names.
bool _hasTag(Candidate c, String name) {
  final wanted = name.toUpperCase();
  return c.tags.any((tag) => tag.toUpperCase() == wanted);
}
