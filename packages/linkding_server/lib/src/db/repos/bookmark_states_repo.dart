import 'package:dust_dart/db.dart';

import '../rows/bookmark_rows.dart';

part 'bookmark_states_repo.g.dart';

/// Archived, unread and shared: one bookmark's buttons, and the bulk actions
/// on the owner's bookmarks among a list of ids.
@SqlxDao()
abstract final class BookmarkStatesRepo {
  const factory BookmarkStatesRepo(Executor db) = _$BookmarkStatesRepo;

  @Query(r'''
UPDATE bookmarks_bookmark SET is_archived = $3, date_modified = $4
WHERE owner_id = $1 AND id = ANY($2)
''')
  Future<Result<Unit, SqlxError>> setArchived(
    int ownerId,
    List<int> ids,
    bool archived,
    DateTime now,
  );

  @Query(r'''
UPDATE bookmarks_bookmark SET unread = $3, date_modified = $4
WHERE owner_id = $1 AND id = ANY($2)
''')
  Future<Result<Unit, SqlxError>> setUnread(
    int ownerId,
    List<int> ids,
    bool unread,
    DateTime now,
  );

  @Query(r'''
UPDATE bookmarks_bookmark SET shared = $3, date_modified = $4
WHERE owner_id = $1 AND id = ANY($2)
''')
  Future<Result<Unit, SqlxError>> setShared(
    int ownerId,
    List<int> ids,
    bool shared,
    DateTime now,
  );

  /// The status checkboxes of the details view, and the single unshare and
  /// mark-as-read buttons: saved without touching `date_modified`.
  @Query(r'''
UPDATE bookmarks_bookmark SET is_archived = $3, unread = $4, shared = $5
WHERE id = $1 AND owner_id = $2
''')
  Future<Result<Unit, SqlxError>> setState(
    int id,
    int ownerId,
    bool isArchived,
    bool unread,
    bool shared,
  );

  /// Marks a bookmark read by opening it: no change to `date_modified`.
  @Query(r'''
UPDATE bookmarks_bookmark SET unread = false WHERE id = $1 AND owner_id = $2
''')
  Future<Result<Unit, SqlxError>> markRead(int id, int ownerId);

  @Query(r'''
UPDATE bookmarks_bookmark SET date_modified = $3
WHERE owner_id = $1 AND id = ANY($2)
''')
  Future<Result<Unit, SqlxError>> touch(
    int ownerId,
    List<int> ids,
    DateTime now,
  );

  /// The owner's bookmarks among [ids].
  @Query(r'''
SELECT id FROM bookmarks_bookmark WHERE owner_id = $1 AND id = ANY($2)
ORDER BY id
''')
  Future<Result<List<IdRow>, SqlxError>> ownedIds(int ownerId, List<int> ids);
}
