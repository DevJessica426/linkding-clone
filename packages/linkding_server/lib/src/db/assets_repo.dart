import 'package:dust_dart/db.dart';

import 'rows.dart';

part 'assets_repo.g.dart';

/// Snapshots and uploaded files of bookmarks.
@SqlxDao()
abstract final class AssetsRepo {
  const factory AssetsRepo(Executor db) = _$AssetsRepo;

  @Query(r'''
SELECT id, date_created, file, file_size, asset_type, content_type,
       display_name, status, gzip, bookmark_id
FROM bookmarks_bookmarkasset WHERE id = $1
''')
  Future<Result<AssetRow?, SqlxError>> byId(int id);

  /// An asset of one of the owner's bookmarks: `access.asset_write`.
  @Query(r'''
SELECT a.id, a.date_created, a.file, a.file_size, a.asset_type,
       a.content_type, a.display_name, a.status, a.gzip, a.bookmark_id
FROM bookmarks_bookmarkasset a
JOIN bookmarks_bookmark b ON b.id = a.bookmark_id
WHERE a.id = $1 AND b.owner_id = $2
''')
  Future<Result<AssetRow?, SqlxError>> owned(int id, int ownerId);

  /// An asset of one of the owner's bookmarks, looked up through that
  /// bookmark, as the API's nested asset routes do.
  @Query(r'''
SELECT a.id, a.date_created, a.file, a.file_size, a.asset_type,
       a.content_type, a.display_name, a.status, a.gzip, a.bookmark_id
FROM bookmarks_bookmarkasset a
JOIN bookmarks_bookmark b ON b.id = a.bookmark_id
WHERE a.id = $1 AND a.bookmark_id = $2 AND b.owner_id = $3
''')
  Future<Result<AssetRow?, SqlxError>> ofBookmark(
    int id,
    int bookmarkId,
    int ownerId,
  );

  @Query(r'''
INSERT INTO bookmarks_bookmarkasset (
  date_created, file, file_size, asset_type, content_type, display_name,
  status, gzip, bookmark_id)
VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
RETURNING id, date_created, file, file_size, asset_type, content_type,
          display_name, status, gzip, bookmark_id
''')
  Future<Result<AssetRow, SqlxError>> insert(
    DateTime dateCreated,
    String file,
    int? fileSize,
    String assetType,
    String contentType,
    String displayName,
    String status,
    bool gzip,
    int bookmarkId,
  );

  /// Removes an asset, pointing its bookmark's latest snapshot at the next
  /// newest complete snapshot when it was that one, and marks the bookmark
  /// modified.
  @Query(r'''
WITH gone AS (
  DELETE FROM bookmarks_bookmarkasset WHERE id = $1 RETURNING id, bookmark_id
)
UPDATE bookmarks_bookmark b SET
  date_modified = $2,
  latest_snapshot_id = CASE
    WHEN b.latest_snapshot_id = (SELECT id FROM gone) THEN (
      SELECT a.id FROM bookmarks_bookmarkasset a
      WHERE a.bookmark_id = b.id AND a.asset_type = 'snapshot'
        AND a.status = 'complete' AND a.id <> (SELECT id FROM gone)
      ORDER BY a.date_created DESC
      LIMIT 1)
    ELSE b.latest_snapshot_id
  END
WHERE b.id = (SELECT bookmark_id FROM gone)
''')
  Future<Result<Unit, SqlxError>> delete(int id, DateTime now);

  /// Points a bookmark at its newest snapshot, and marks it modified.
  @Query(r'''
UPDATE bookmarks_bookmark SET latest_snapshot_id = $2, date_modified = $3
WHERE id = $1
''')
  Future<Result<Unit, SqlxError>> setLatestSnapshot(
    int bookmarkId,
    int assetId,
    DateTime now,
  );

  @Query(r'UPDATE bookmarks_bookmark SET date_modified = $2 WHERE id = $1')
  Future<Result<Unit, SqlxError>> touchBookmark(int bookmarkId, DateTime now);
}
