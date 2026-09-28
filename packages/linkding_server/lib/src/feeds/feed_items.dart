import 'package:dust_dart/db.dart';

import '../core/profile.dart';
import '../db/rows.dart';
import '../db/users_repo.dart';
import '../services/errors.dart';
import '../services/search.dart';

/// The four feeds of linkding's `feeds.py`, with their titles and
/// descriptions.
enum FeedKind {
  all('All bookmarks', 'All bookmarks'),
  unread('Unread bookmarks', 'All unread bookmarks'),
  shared('Shared bookmarks', 'All shared bookmarks'),
  publicShared('Public shared bookmarks', 'All public shared bookmarks');

  const FeedKind(this.title, this.description);

  final String title;
  final String description;
}

/// Each feed's query set: a feed token owner's active (or unread)
/// bookmarks, what users share with them, or what is shared publicly.
Future<List<Candidate>> feedItems(
  Executor db,
  FeedKind kind,
  BookmarkSearch search,
  UserRow? tokenUser,
) async {
  final searches = BookmarkSearchQuery(db);
  Future<Profile> profileOf(int userId) async =>
      Profile((await UsersRepo(db).profile(userId)).orThrow ?? standardProfile);

  switch (kind) {
    case FeedKind.all || FeedKind.unread:
      final user = tokenUser!;
      final items = await searches.run(
        list: BookmarkList.active,
        search: search,
        profile: await profileOf(user.id),
        ownerId: user.id,
      );
      return kind == FeedKind.unread
          ? [
              for (final item in items)
                if (item.row.unread) item,
            ]
          : items;
    case FeedKind.shared || FeedKind.publicShared:
      // `resolve_user`: an unknown user name means no bookmarks at all.
      int? ownerId;
      if (search.user.isNotEmpty) {
        final owner = (await UsersRepo(db).byUsername(search.user)).orThrow;
        if (owner == null) return const [];
        ownerId = owner.id;
      }
      final publicOnly = kind == FeedKind.publicShared;
      return searches.run(
        list: BookmarkList.shared,
        search: search,
        profile: publicOnly
            ? const Profile(standardProfile)
            : await profileOf(tokenUser!.id),
        ownerId: ownerId,
        publicOnly: publicOnly,
      );
  }
}
