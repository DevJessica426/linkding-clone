import 'package:linkding_shared/linkding_shared.dart';

import '../core/profile.dart';
import '../db/rows/rows.dart';
import 'bookmark_search.dart';

/// The search expression (or legacy query) and bundle of one search.
final class SearchFilter {
  SearchFilter(
    this.expression,
    this.legacy,
    this.bundle,
    this.lax,
    this.nothing,
  );

  factory SearchFilter.of(BookmarkSearch search, Profile? profile) {
    final lax = profile?.laxTags ?? false;
    if (profile?.legacySearch ?? false) {
      return SearchFilter(
        null,
        LegacyQuery.parse(search.q),
        search.bundle,
        lax,
        false,
      );
    }
    try {
      return SearchFilter(
        parseSearchQuery(search.q),
        null,
        search.bundle,
        lax,
        false,
      );
    } on SearchQueryParseError {
      // linkding answers a query it cannot parse with no results.
      return SearchFilter(null, null, search.bundle, lax, true);
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
