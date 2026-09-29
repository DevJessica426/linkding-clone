import 'package:dust_dart/db.dart';

import '../db/repos/bookmark_list_repo.dart';
import '../db/repos/bookmark_tags_repo.dart';
import '../db/repos/bookmarks_repo.dart';
import '../db/or_throw.dart';
import '../db/rows/rows.dart';
import '../db/repos/tags_repo.dart';
import 'bookmark_copy.dart';
import 'netscape_bookmark.dart';
import 'netscape_parser.dart';

/// What an import did.
final class ImportResult {
  int total = 0;
  int success = 0;
  int failed = 0;
  final importedUrls = <String>{};
}

/// linkding's `import_netscape_html`: tags first, then bookmarks in
/// batches of 200, updating those whose normalized URL is already saved.
Future<ImportResult> importNetscape(
  Executor db,
  String source,
  int ownerId, {
  required bool mapPrivateFlag,
  required bool disableUrlValidation,
}) async {
  final result = ImportResult();
  final parsed = parseNetscape(source);
  final tags = TagsRepo(db);

  // The tag cache: every tag of the owner by lowercase name, the later one
  // winning.
  Future<Map<String, TagRow>> tagCache() async => {
    for (final tag in (await tags.all(ownerId)).orThrow)
      tag.name.toLowerCase(): tag,
  };

  var cache = await tagCache();
  for (final bookmark in parsed) {
    for (final name in bookmark.tagNames) {
      if (name.runes.length > 64) continue;
      if (cache.containsKey(name.toLowerCase())) continue;
      cache[name.toLowerCase()] = (await tags.insert(
        name,
        DateTime.now().toUtc(),
        ownerId,
      )).orThrow;
    }
  }
  cache = await tagCache();

  final repo = BookmarksRepo(db);
  final lists = BookmarkListRepo(db);
  for (var offset = 0; offset < parsed.length; offset += 200) {
    final batch = parsed.sublist(
      offset,
      offset + 200 > parsed.length ? parsed.length : offset + 200,
    );
    final urls = [for (final b in batch) b.hrefNormalized];
    final existing = (await lists.withNormalizedUrls(ownerId, urls)).orThrow;
    final imported = <NetscapeBookmark>[];
    final updates = <(BookmarkRow, CopiedBookmark)>[];
    final creates = <CopiedBookmark>[];

    for (final bookmark in batch) {
      result.total++;
      if (result.importedUrls.contains(bookmark.hrefNormalized)) {
        result.failed++;
        continue;
      }
      final saved = existing
          .where((b) => b.urlNormalized == bookmark.hrefNormalized)
          .firstOrNull;
      final copied = copyBookmarkData(bookmark, saved, mapPrivateFlag);
      if (copied == null ||
          !isValidBookmark(
            copied,
            disableUrlValidation: disableUrlValidation,
          )) {
        result.failed++;
        continue;
      }
      if (saved != null) {
        updates.add((saved, copied));
      } else {
        creates.add(copied);
      }
      result.success++;
      result.importedUrls.add(bookmark.hrefNormalized);
      imported.add(bookmark);
    }

    for (final (saved, c) in updates) {
      (await lists.importUpdate(
        saved.id,
        c.url,
        c.urlNormalized,
        c.dateAdded,
        c.dateModified,
        c.unread,
        c.shared,
        c.title,
        c.description,
        c.notes,
      )).orThrow;
    }
    for (final c in creates) {
      (await repo.insert(
        c.url,
        c.urlNormalized,
        c.title,
        c.description,
        c.notes,
        c.unread,
        c.isArchived,
        c.shared,
        c.dateAdded,
        c.dateModified,
        ownerId,
      )).orThrow;
    }

    final saved = (await lists.withNormalizedUrls(ownerId, urls)).orThrow;
    for (final bookmark in imported) {
      final row = saved
          .where((b) => b.urlNormalized == bookmark.hrefNormalized)
          .firstOrNull;
      if (row == null) continue;
      final tagIds = <int>[];
      for (final name in bookmark.tagNames) {
        final tag = cache[name.toLowerCase()];
        if (tag != null && !tagIds.contains(tag.id)) tagIds.add(tag.id);
      }
      if (tagIds.isNotEmpty) {
        (await BookmarkTagsRepo(db).linkTags(row.id, tagIds)).orThrow;
      }
    }
  }
  return result;
}
