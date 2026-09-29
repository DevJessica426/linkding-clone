import 'package:dust_dart/db.dart';

import '../../db/repos/bookmarks_repo.dart';
import '../../db/or_throw.dart';
import '../../db/repos/profiles_repo.dart';
import '../../db/rows/rows.dart';
import '../../pages/session/visitor.dart';

/// linkding's `access.bookmark_read`: the visitor's own bookmark, or one
/// shared by an owner who shares with other users (for a signed-in
/// visitor) or publicly. Changing someone else's bookmark is never allowed,
/// so a `POST` finds only the visitor's own.
Future<BookmarkRow?> readableBookmark(
  Executor db,
  Visitor visitor,
  int id,
) async {
  final bookmark = (await BookmarksRepo(db).byId(id)).orThrow;
  if (bookmark == null) return null;
  if (bookmark.ownerId == visitor.user?.id) return bookmark;
  if (!bookmark.shared || visitor.request.method == 'POST') return null;
  final owner = (await ProfilesRepo(db).profile(bookmark.ownerId)).orThrow;
  if (owner == null) return null;
  final visible =
      (visitor.isAuthenticated && owner.enableSharing) ||
      owner.enablePublicSharing;
  return visible ? bookmark : null;
}
