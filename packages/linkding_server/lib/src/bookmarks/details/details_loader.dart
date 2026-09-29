import 'package:dust_dart/db.dart';

import '../../db/repos/assets_repo.dart';
import '../../db/repos/bookmark_tags_repo.dart';
import '../../db/or_throw.dart';
import '../../pages/session/visitor.dart';
import '../service/bookmark_access.dart';
import '../lists/list_page.dart';

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
  final tags = (await BookmarkTagsRepo(db).tagNames([bookmark.id])).orThrow;
  return Details(
    bookmark: bookmark,
    tags: [for (final t in tags) t.name]..sort(),
    assets: (await AssetsRepo(db).forBookmark(bookmark.id)).orThrow,
    isEditable: bookmark.ownerId == visitor.user?.id,
    uploadsEnabled: uploadsEnabled,
  );
}
