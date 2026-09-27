import 'package:dust_dart/db.dart';

import 'rows.dart';

part 'bookmarks_repo.g.dart';

/// Every fixed query about bookmarks. Searching is dynamic SQL and lives in
/// `BookmarkSearchQuery`.
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

  /// Tag names for a page of bookmarks.
  @Query(r'''
SELECT bt.bookmark_id, t.name
FROM bookmarks_bookmark_tags bt JOIN bookmarks_tag t ON t.id = bt.tag_id
WHERE bt.bookmark_id = ANY($1)
''')
  Future<Result<List<BookmarkTagRow>, SqlxError>> tagNames(
    List<int> bookmarkIds,
  );

  /// Removes the links to tags not in [tagIds]; `tags.set()`, first half.
  @Query(r'''
DELETE FROM bookmarks_bookmark_tags
WHERE bookmark_id = $1 AND NOT (tag_id = ANY($2))
''')
  Future<Result<Unit, SqlxError>> unlinkOtherTags(
    int bookmarkId,
    List<int> tagIds,
  );

  /// Adds links to [tagIds] that are missing; `tags.set()`, second half.
  @Query(r'''
INSERT INTO bookmarks_bookmark_tags (bookmark_id, tag_id)
SELECT $1, tag_id FROM unnest($2::integer[]) AS tag_id
ON CONFLICT (bookmark_id, tag_id) DO NOTHING
''')
  Future<Result<Unit, SqlxError>> linkTags(int bookmarkId, List<int> tagIds);

  // --- Bulk actions, on the owner's bookmarks among [ids] ---

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

  /// Links every one of [bookmarkIds] to every one of [tagIds].
  @Query(r'''
INSERT INTO bookmarks_bookmark_tags (bookmark_id, tag_id)
SELECT b, t FROM unnest($1::integer[]) AS b, unnest($2::integer[]) AS t
ON CONFLICT (bookmark_id, tag_id) DO NOTHING
''')
  Future<Result<Unit, SqlxError>> linkAll(
    List<int> bookmarkIds,
    List<int> tagIds,
  );

  @Query(r'''
DELETE FROM bookmarks_bookmark_tags
WHERE bookmark_id = ANY($1) AND tag_id = ANY($2)
''')
  Future<Result<Unit, SqlxError>> unlinkAll(
    List<int> bookmarkIds,
    List<int> tagIds,
  );

  /// The bookmarks of one list, before the search query and bundle are
  /// applied, in the requested order.
  ///
  /// `$1` is the owner, or null for everyone's shared bookmarks. `$2` is the
  /// list: `active`, `archived` or `shared` (`$3` then limits it to owners
  /// who share publicly). `$4`/`$5` are `modified_since`/`added_since`, `$6`
  /// and `$7` the unread and shared filters (`yes`, `no`, anything else for
  /// off), and `$8` the sort; an unknown sort is newest first. Ties are
  /// broken by id so pages never overlap.
  @Query(r'''
SELECT b.id, b.url, b.url_normalized, b.title, b.description, b.notes,
       b.web_archive_snapshot_url, b.favicon_file, b.preview_image_file,
       b.unread, b.is_archived, b.shared, b.date_added, b.date_modified,
       b.date_accessed, b.owner_id, b.latest_snapshot_id
FROM bookmarks_bookmark b
WHERE ($1::integer IS NULL OR b.owner_id = $1)
  AND CASE $2::text
        WHEN 'active' THEN NOT b.is_archived
        WHEN 'archived' THEN b.is_archived
        ELSE b.shared AND EXISTS (
          SELECT 1 FROM bookmarks_userprofile p
          WHERE p.user_id = b.owner_id AND p.enable_sharing
            AND (NOT $3::boolean OR p.enable_public_sharing))
      END
  AND ($4::timestamptz IS NULL OR b.date_modified > $4)
  AND ($5::timestamptz IS NULL OR b.date_added > $5)
  AND ($6::text NOT IN ('yes', 'no') OR b.unread = ($6 = 'yes'))
  AND ($7::text NOT IN ('yes', 'no') OR b.shared = ($7 = 'yes'))
ORDER BY
  CASE WHEN $8::text = 'title_asc' THEN
    CASE WHEN b.title <> '' THEN lower(b.title) ELSE lower(b.url) END END ASC,
  CASE WHEN $8 = 'title_desc' THEN
    CASE WHEN b.title <> '' THEN lower(b.title) ELSE lower(b.url) END END DESC,
  CASE WHEN $8 = 'added_asc' THEN b.date_added END ASC,
  CASE WHEN $8 = 'modified_asc' THEN b.date_modified END ASC,
  CASE WHEN $8 = 'modified_desc' THEN b.date_modified END DESC,
  CASE WHEN $8 NOT IN ('title_asc', 'title_desc', 'added_asc',
                       'modified_asc', 'modified_desc')
       THEN b.date_added END DESC,
  CASE WHEN $8 IN ('title_asc', 'added_asc', 'modified_asc') THEN b.id END ASC,
  b.id DESC
''')
  Future<Result<List<BookmarkRow>, SqlxError>> list(
    int? ownerId,
    String list,
    bool publicOnly,
    DateTime? modifiedSince,
    DateTime? addedSince,
    String unread,
    String shared,
    String sort,
  );

  /// Every bookmark of an owner, oldest first, for the export.
  @Query(r'''
SELECT id, url, url_normalized, title, description, notes,
       web_archive_snapshot_url, favicon_file, preview_image_file, unread,
       is_archived, shared, date_added, date_modified, date_accessed, owner_id,
       latest_snapshot_id
FROM bookmarks_bookmark WHERE owner_id = $1 ORDER BY id
''')
  Future<Result<List<BookmarkRow>, SqlxError>> allOwned(int ownerId);
}
