import 'package:dust_dart/db.dart';

import '../db/bookmarks_repo.dart';
import '../db/rows.dart';
import '../db/users_repo.dart';
import '../services/errors.dart';
import 'context.dart';

/// linkding's `access.bookmark_read`: the visitor's own bookmark, or one
/// shared by an owner who shares with other users (for a signed-in
/// visitor) or publicly. Changing someone else's bookmark is never allowed,
/// so a `POST` finds only the visitor's own.
Future<BookmarkRow?> readableBookmark(
  Executor db,
  PageContext c,
  int id,
) async {
  final bookmark = (await BookmarksRepo(db).byId(id)).orThrow;
  if (bookmark == null) return null;
  if (bookmark.ownerId == c.user?.id) return bookmark;
  if (!bookmark.shared || c.request.method == 'POST') return null;
  final owner = (await UsersRepo(db).profile(bookmark.ownerId)).orThrow;
  if (owner == null) return null;
  final visible =
      (c.isAuthenticated && owner.enableSharing) || owner.enablePublicSharing;
  return visible ? bookmark : null;
}
