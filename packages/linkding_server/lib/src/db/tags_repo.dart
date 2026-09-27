import 'package:dust_dart/db.dart';

import 'rows.dart';

part 'tags_repo.g.dart';

/// Tags. Names compare ignoring case the way Django's `iexact` does on
/// PostgreSQL: `UPPER(name::text) = UPPER($n)`.
@SqlxDao()
abstract final class TagsRepo {
  const factory TagsRepo(Executor db) = _$TagsRepo;

  /// The owner's tag with this name in any case; the oldest if a legacy
  /// database holds several.
  @Query(r'''
SELECT id, name, date_added, owner_id FROM bookmarks_tag
WHERE owner_id = $1 AND UPPER(name::text) = UPPER($2)
ORDER BY id
LIMIT 1
''')
  Future<Result<TagRow?, SqlxError>> named(int ownerId, String name);

  /// The owner's tags named in a search query; `get_tags_for_query`.
  @Query(r'''
SELECT id, name, date_added, owner_id FROM bookmarks_tag
WHERE owner_id = $1
  AND UPPER(name::text) IN (SELECT UPPER(n) FROM unnest($2::text[]) AS n)
ORDER BY id
''')
  Future<Result<List<TagRow>, SqlxError>> withNames(
    int ownerId,
    List<String> names,
  );

  /// Tags named in a search query among shared bookmarks, of one owner or
  /// of everyone; `get_shared_tags_for_query`.
  @Query(r'''
SELECT DISTINCT t.id, t.name, t.date_added, t.owner_id
FROM bookmarks_tag t
JOIN bookmarks_bookmark_tags bt ON bt.tag_id = t.id
JOIN bookmarks_bookmark b ON b.id = bt.bookmark_id
JOIN bookmarks_userprofile p ON p.user_id = b.owner_id
WHERE b.shared AND p.enable_sharing
  AND (NOT $2::boolean OR p.enable_public_sharing)
  AND ($1::integer IS NULL OR b.owner_id = $1)
  AND UPPER(t.name::text) IN (SELECT UPPER(n) FROM unnest($3::text[]) AS n)
ORDER BY t.id
''')
  Future<Result<List<TagRow>, SqlxError>> sharedNamed(
    int? ownerId,
    bool publicOnly,
    List<String> names,
  );

  @Query(r'''
INSERT INTO bookmarks_tag (name, date_added, owner_id) VALUES ($1, $2, $3)
RETURNING id, name, date_added, owner_id
''')
  Future<Result<TagRow, SqlxError>> insert(
    String name,
    DateTime dateAdded,
    int ownerId,
  );

  @Query(r'''
SELECT id, name, date_added, owner_id FROM bookmarks_tag
WHERE id = $1 AND owner_id = $2
''')
  Future<Result<TagRow?, SqlxError>> owned(int id, int ownerId);

  /// A page of `/api/tags/`, in creation order.
  @Query(r'''
SELECT id, name, date_added, owner_id FROM bookmarks_tag
WHERE owner_id = $1
ORDER BY id
LIMIT $2 OFFSET $3
''')
  Future<Result<List<TagRow>, SqlxError>> page(
    int ownerId,
    int limit,
    int offset,
  );

  @Query(r'SELECT count(*)::integer FROM bookmarks_tag WHERE owner_id = $1')
  Future<Result<int, SqlxError>> count(int ownerId);

  @Query(r'''
SELECT id, name, date_added, owner_id FROM bookmarks_tag
WHERE owner_id = $1 ORDER BY id
''')
  Future<Result<List<TagRow>, SqlxError>> all(int ownerId);

  /// The tags page: names matching [search] (empty matches all), with how
  /// many bookmarks use each, optionally only unused ones.
  @Query(r'''
SELECT t.id, t.name, t.date_added,
       (SELECT count(*)::integer FROM bookmarks_bookmark_tags bt
        WHERE bt.tag_id = t.id) AS bookmark_count
FROM bookmarks_tag t
WHERE t.owner_id = $1
  AND ($2 = '' OR UPPER(t.name::text) LIKE '%' || UPPER($2) || '%')
  AND (NOT $3 OR NOT EXISTS (
        SELECT 1 FROM bookmarks_bookmark_tags bt WHERE bt.tag_id = t.id))
ORDER BY lower(t.name), t.id
''')
  Future<Result<List<TagUsageRow>, SqlxError>> usage(
    int ownerId,
    String search,
    bool unusedOnly,
  );

  @Query(r'UPDATE bookmarks_tag SET name = $3 WHERE id = $1 AND owner_id = $2')
  Future<Result<Unit, SqlxError>> rename(int id, int ownerId, String name);

  /// Deletes a tag and its links to bookmarks.
  @Query(r'''
WITH gone AS (
  DELETE FROM bookmarks_tag WHERE id = $1 AND owner_id = $2 RETURNING id
)
DELETE FROM bookmarks_bookmark_tags WHERE tag_id IN (SELECT id FROM gone)
''')
  Future<Result<Unit, SqlxError>> delete(int id, int ownerId);

  /// Moves every link from [fromIds] to [intoId], skipping bookmarks that
  /// already carry it, then deletes the merged tags.
  @Query(r'''
WITH moved AS (
  INSERT INTO bookmarks_bookmark_tags (bookmark_id, tag_id)
  SELECT DISTINCT bt.bookmark_id, $2::integer FROM bookmarks_bookmark_tags bt
  WHERE bt.tag_id = ANY($3)
  ON CONFLICT (bookmark_id, tag_id) DO NOTHING
), unlinked AS (
  DELETE FROM bookmarks_bookmark_tags WHERE tag_id = ANY($3)
)
DELETE FROM bookmarks_tag WHERE owner_id = $1 AND id = ANY($3)
''')
  Future<Result<Unit, SqlxError>> merge(
    int ownerId,
    int intoId,
    List<int> fromIds,
  );
}
