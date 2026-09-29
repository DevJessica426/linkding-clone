import 'package:dust_dart/db.dart';

import '../db/bookmarks_repo.dart';
import '../pages/visitor.dart';
import '../services/errors.dart';
import 'bookmark_access.dart';
import 'list_page.dart';

/// linkding's `get_details_context`: the bookmark in `?details=`, when the
/// visitor may see it.
Future<Details?> loadDetails(
  Executor db,
  Visitor visitor,
  String? id, {
  required bool uploadsEnabled,
}) async {
  final bookmarkId = int.tryParse(id ?? '');
  if (bookmarkId == null) return null;
  final bookmark = await readableBookmark(db, visitor, bookmarkId);
  if (bookmark == null) return null;
  final bookmarks = BookmarksRepo(db);
  final tags = (await bookmarks.tagNames([bookmark.id])).orThrow;
  return Details(
    bookmark: bookmark,
    tags: [for (final t in tags) t.name]..sort(),
    assets: (await bookmarks.assets(bookmark.id)).orThrow,
    isEditable: bookmark.ownerId == visitor.user?.id,
    uploadsEnabled: uploadsEnabled,
  );
}
