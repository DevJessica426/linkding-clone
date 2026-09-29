import '../../db/repos/bookmarks_repo.dart';
import '../../db/or_throw.dart';
import '../../db/rows/rows.dart';
import 'bookmark_service.dart';

/// Filling in a bookmark's title and description from its page.
extension BookmarkMetadata on BookmarkService {
  /// `enhance_with_website_metadata`: fills an empty title and description
  /// from the page. `date_modified` is left alone.
  Future<BookmarkRow> enhanceWithMetadata(BookmarkRow row) async {
    if (row.title.isNotEmpty && row.description.isNotEmpty) return row;
    final page = await metadata.load(row.url);
    final title = row.title.isEmpty ? (page.title ?? '') : row.title;
    final description = row.description.isEmpty
        ? (page.description ?? '')
        : row.description;
    return (await BookmarksRepo(db).update(
      row.id,
      row.url,
      row.urlNormalized,
      title,
      description,
      row.notes,
      row.unread,
      row.isArchived,
      row.shared,
      row.dateAdded,
      row.dateModified,
    )).orThrow;
  }

  /// `refresh_bookmarks_metadata`: reloads the title and description of the
  /// owner's bookmarks among [ids] from their pages, keeping a value the
  /// page does not have.
  Future<void> refreshMetadata(int ownerId, List<int> ids) async {
    final repo = BookmarksRepo(db);
    for (final id in ids) {
      final row = (await repo.owned(id, ownerId)).orThrow;
      if (row == null) continue;
      final page = await metadata.load(row.url);
      final title = page.title;
      final description = page.description;
      (await repo.update(
        row.id,
        row.url,
        row.urlNormalized,
        title != null && title.isNotEmpty ? title : row.title,
        description != null && description.isNotEmpty
            ? description
            : row.description,
        row.notes,
        row.unread,
        row.isArchived,
        row.shared,
        row.dateAdded,
        DateTime.now().toUtc(),
      )).orThrow;
    }
  }
}
