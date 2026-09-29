import 'package:dust_dart/db.dart';

import '../rows/bookmark_rows.dart';

part 'bookmarks_repo.g.dart';

/// Reading and saving a bookmark. A search reads one list with
/// `BookmarkListRepo.list`, and `BookmarkSearchQuery` applies the search
/// expression to it.
///
/// linkding's foreign keys do not cascade (Django emulates cascades in
/// Python), so deleting a bookmark removes its tag links and assets in the
/// same statement.
@SqlxDao()
abstract final class BookmarksRepo {
  const factory BookmarksRepo(Executor db) = _$BookmarksRepo;

  /// A bookmark its owner can read or change.
  @Query(r'''
SELECT id, url, url_normalized, title, description, notes,
       web_archive_snapshot_url, favicon_file, preview_image_file, unread,
       is_archived, shared, date_added, date_modified, date_accessed, owner_id,
       latest_snapshot_id
FROM bookmarks_bookmark WHERE id = $1 AND owner_id = $2
''')
  Future<Result<BookmarkRow?, SqlxError>> owned(int id, int ownerId);

  /// Any bookmark by id, for pages that decide access themselves.
  @Query(r'''
SELECT id, url, url_normalized, title, description, notes,
       web_archive_snapshot_url, favicon_file, preview_image_file, unread,
       is_archived, shared, date_added, date_modified, date_accessed, owner_id,
       latest_snapshot_id
FROM bookmarks_bookmark WHERE id = $1
''')
  Future<Result<BookmarkRow?, SqlxError>> byId(int id);

  /// The bookmark already saved for a URL: `Bookmark.query_existing`, which
  /// compares normalized URLs and falls back to the exact URL for rows saved
  /// before normalization existed. The oldest one wins, as `.first()` does.
  @Query(r'''
SELECT id, url, url_normalized, title, description, notes,
       web_archive_snapshot_url, favicon_file, preview_image_file, unread,
       is_archived, shared, date_added, date_modified, date_accessed, owner_id,
       latest_snapshot_id
FROM bookmarks_bookmark
WHERE owner_id = $1
  AND (url_normalized = $2 OR (url_normalized = '' AND url = $3))
ORDER BY id
LIMIT 1
''')
  Future<Result<BookmarkRow?, SqlxError>> existing(
    int ownerId,
    String normalizedUrl,
    String url,
  );

  /// Whether another of the owner's bookmarks has exactly this URL; editing
  /// one into a duplicate is refused.
  @Query(r'''
SELECT EXISTS (
  SELECT 1 FROM bookmarks_bookmark
  WHERE owner_id = $1 AND url = $2 AND id <> $3
) AS taken
''')
  Future<Result<bool, SqlxError>> urlTaken(int ownerId, String url, int id);

  /// Whether another of the owner's bookmarks is saved for this URL, compared
  /// as [existing] compares: editing a bookmark into a duplicate is refused.
  @Query(r'''
SELECT EXISTS (
  SELECT 1 FROM bookmarks_bookmark
  WHERE owner_id = $1
    AND (url_normalized = $2 OR (url_normalized = '' AND url = $3))
    AND id <> $4
) AS duplicate
''')
  Future<Result<bool, SqlxError>> duplicate(
    int ownerId,
    String normalizedUrl,
    String url,
    int id,
  );

  @Query(r'''
INSERT INTO bookmarks_bookmark (
  url, url_normalized, title, description, notes, website_title,
  website_description, web_archive_snapshot_url, favicon_file,
  preview_image_file, unread, is_archived, shared, date_added, date_modified,
  date_accessed, owner_id, latest_snapshot_id)
VALUES ($1, $2, $3, $4, $5, NULL, NULL, '', '', '', $6, $7, $8, $9, $10, NULL,
        $11, NULL)
RETURNING id, url, url_normalized, title, description, notes,
          web_archive_snapshot_url, favicon_file, preview_image_file, unread,
          is_archived, shared, date_added, date_modified, date_accessed,
          owner_id, latest_snapshot_id
''')
  Future<Result<BookmarkRow, SqlxError>> insert(
    String url,
    String urlNormalized,
    String title,
    String description,
    String notes,
    bool unread,
    bool isArchived,
    bool shared,
    DateTime dateAdded,
    DateTime dateModified,
    int ownerId,
  );

  /// Saves every editable field, as Django's `save()` does.
  @Query(r'''
UPDATE bookmarks_bookmark SET
  url = $2, url_normalized = $3, title = $4, description = $5, notes = $6,
  unread = $7, is_archived = $8, shared = $9, date_added = $10,
  date_modified = $11
WHERE id = $1
RETURNING id, url, url_normalized, title, description, notes,
          web_archive_snapshot_url, favicon_file, preview_image_file, unread,
          is_archived, shared, date_added, date_modified, date_accessed,
          owner_id, latest_snapshot_id
''')
  Future<Result<BookmarkRow, SqlxError>> update(
    int id,
    String url,
    String urlNormalized,
    String title,
    String description,
    String notes,
    bool unread,
    bool isArchived,
    bool shared,
    DateTime dateAdded,
    DateTime dateModified,
  );

  /// Deletes a bookmark with its tag links and assets. Returns the asset
  /// file names, for removing the files too.
  @Query(r'''
WITH gone AS (
  DELETE FROM bookmarks_bookmark WHERE id = $1 AND owner_id = $2 RETURNING id
), links AS (
  DELETE FROM bookmarks_bookmark_tags WHERE bookmark_id IN (SELECT id FROM gone)
)
DELETE FROM bookmarks_bookmarkasset
WHERE bookmark_id IN (SELECT id FROM gone)
RETURNING file
''')
  Future<Result<List<FileRow>, SqlxError>> delete(int id, int ownerId);
}
