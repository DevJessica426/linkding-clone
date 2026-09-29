import 'package:dust_dart/db.dart';

import '../db/repos/bundles_repo.dart';
import '../db/or_throw.dart';
import '../db/rows/rows.dart';

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

/// A bookmark with its tags, as the search sees it.
final class Candidate {
  Candidate(this.row, this.tagRows)
    : tags = [for (final tag in tagRows) tag.name];

  final BookmarkRow row;
  final List<BookmarkTagRow> tagRows;

  /// The tag names, for matching.
  final List<String> tags;
}
