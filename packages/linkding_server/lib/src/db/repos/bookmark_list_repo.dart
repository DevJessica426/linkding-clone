import 'package:dust_dart/db.dart';

import '../rows/bookmark_rows.dart';

part 'bookmark_list_repo.g.dart';

/// The bookmarks of a list, for searching, exporting and importing.
@SqlxDao()
abstract final class BookmarkListRepo {
  const factory BookmarkListRepo(Executor db) = _$BookmarkListRepo;

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

  /// Every bookmark of an owner, for the export, in table order as Django
  /// lists a query without an ordering.
  @Query(r'''
SELECT id, url, url_normalized, title, description, notes,
       web_archive_snapshot_url, favicon_file, preview_image_file, unread,
       is_archived, shared, date_added, date_modified, date_accessed, owner_id,
       latest_snapshot_id
FROM bookmarks_bookmark WHERE owner_id = $1
''')
  Future<Result<List<BookmarkRow>, SqlxError>> allOwned(int ownerId);

  /// The owner's bookmarks saved for any of [normalizedUrls], in table
  /// order: the import's lookup of what it updates.
  @Query(r'''
SELECT id, url, url_normalized, title, description, notes,
       web_archive_snapshot_url, favicon_file, preview_image_file, unread,
       is_archived, shared, date_added, date_modified, date_accessed, owner_id,
       latest_snapshot_id
FROM bookmarks_bookmark WHERE owner_id = $1 AND url_normalized = ANY($2)
''')
  Future<Result<List<BookmarkRow>, SqlxError>> withNormalizedUrls(
    int ownerId,
    List<String> normalizedUrls,
  );

  /// The fields an import updates on a bookmark it already has; the
  /// archived state is not among them, as in linkding.
  @Query(r'''
UPDATE bookmarks_bookmark SET
  url = $2, url_normalized = $3, date_added = $4, date_modified = $5,
  unread = $6, shared = $7, title = $8, description = $9, notes = $10
WHERE id = $1
''')
  Future<Result<Unit, SqlxError>> importUpdate(
    int id,
    String url,
    String urlNormalized,
    DateTime dateAdded,
    DateTime dateModified,
    bool unread,
    bool shared,
    String title,
    String description,
    String notes,
  );
}
