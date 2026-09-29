import 'package:dust_dart/db.dart';

import '../compat/django.dart';
import '../core/profile.dart';
import '../db/repos/bookmark_list_repo.dart';
import '../db/repos/bookmark_tags_repo.dart';
import '../db/or_throw.dart';
import '../db/rows/rows.dart';
import 'bookmark_search.dart';
import 'search_filter.dart';

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
    final rows = (await BookmarkListRepo(db).list(
      ownerId,
      list.name,
      publicOnly,
      parseSinceFilter(search.modifiedSince),
      parseSinceFilter(search.addedSince),
      search.unread,
      search.shared,
      search.sort,
    )).orThrow;

    final tagsById = <int, List<BookmarkTagRow>>{};
    if (rows.isNotEmpty) {
      final tagRows = (await BookmarkTagsRepo(
        db,
      ).tagNames([for (final r in rows) r.id])).orThrow;
      for (final tag in tagRows) {
        (tagsById[tag.bookmarkId] ??= []).add(tag);
      }
    }
    final candidates = [
      for (final row in rows) Candidate(row, tagsById[row.id] ?? const []),
    ];

    final filter = SearchFilter.of(search, profile);
    return [
      for (final candidate in candidates)
        if (filter.matches(candidate)) candidate,
    ];
  }
}
