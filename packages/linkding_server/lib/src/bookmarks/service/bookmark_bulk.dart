import 'package:linkding_shared/linkding_shared.dart';

import '../../db/repos/bookmark_states_repo.dart';
import '../../db/repos/bookmark_tags_repo.dart';
import '../../db/or_throw.dart';
import '../../tags/tag_service.dart';
import 'bookmark_service.dart';

/// The bulk actions of the list pages, on the owner's bookmarks among a
/// list of ids.
extension BulkBookmarkActions on BookmarkService {
  /// `archive_bookmark` / `unarchive_bookmark`.
  Future<void> setArchived(int ownerId, List<int> ids, bool archived) async =>
      (await BookmarkStatesRepo(
        db,
      ).setArchived(ownerId, ids, archived, DateTime.now().toUtc())).orThrow;

  Future<void> setUnread(int ownerId, List<int> ids, bool unread) async =>
      (await BookmarkStatesRepo(
        db,
      ).setUnread(ownerId, ids, unread, DateTime.now().toUtc())).orThrow;

  Future<void> setShared(int ownerId, List<int> ids, bool shared) async =>
      (await BookmarkStatesRepo(
        db,
      ).setShared(ownerId, ids, shared, DateTime.now().toUtc())).orThrow;

  /// `tag_bookmarks`: adds the tags in [tagString] to the owner's
  /// bookmarks among [ids].
  Future<void> tag(int ownerId, List<int> ids, String tagString) =>
      transaction((tx) async {
        final states = BookmarkStatesRepo(tx);
        final owned = [
          for (final r in (await states.ownedIds(ownerId, ids)).orThrow) r.id,
        ];
        final tags = await getOrCreateTags(
          tx,
          ownerId,
          parseTagString(tagString),
        );
        (await BookmarkTagsRepo(
          tx,
        ).linkAll(owned, [for (final t in tags) t.id])).orThrow;
        (await states.touch(ownerId, owned, DateTime.now().toUtc())).orThrow;
      });

  /// `untag_bookmarks`.
  Future<void> untag(int ownerId, List<int> ids, String tagString) =>
      transaction((tx) async {
        final states = BookmarkStatesRepo(tx);
        final owned = [
          for (final r in (await states.ownedIds(ownerId, ids)).orThrow) r.id,
        ];
        final tags = await getOrCreateTags(
          tx,
          ownerId,
          parseTagString(tagString),
        );
        (await BookmarkTagsRepo(
          tx,
        ).unlinkAll(owned, [for (final t in tags) t.id])).orThrow;
        (await states.touch(ownerId, owned, DateTime.now().toUtc())).orThrow;
      });
}
