import 'package:dust_dart/db.dart';

import 'rows.dart';

part 'bundles_repo.g.dart';

/// Bundles, kept numbered 0, 1, 2... in `order`.
@SqlxDao()
abstract final class BundlesRepo {
  const factory BundlesRepo(Executor db) = _$BundlesRepo;

  @Query(r'''
SELECT id, name, search, any_tags, all_tags, excluded_tags, filter_unread,
       filter_shared, "order", date_created, date_modified, owner_id
FROM bookmarks_bookmarkbundle WHERE owner_id = $1
ORDER BY "order", id
''')
  Future<Result<List<BundleRow>, SqlxError>> all(int ownerId);

  @Query(r'''
SELECT id, name, search, any_tags, all_tags, excluded_tags, filter_unread,
       filter_shared, "order", date_created, date_modified, owner_id
FROM bookmarks_bookmarkbundle WHERE owner_id = $1
ORDER BY "order", id
LIMIT $2 OFFSET $3
''')
  Future<Result<List<BundleRow>, SqlxError>> page(
    int ownerId,
    int limit,
    int offset,
  );

  @Query(r'''
SELECT count(*)::integer FROM bookmarks_bookmarkbundle WHERE owner_id = $1
''')
  Future<Result<int, SqlxError>> count(int ownerId);

  @Query(r'''
SELECT id, name, search, any_tags, all_tags, excluded_tags, filter_unread,
       filter_shared, "order", date_created, date_modified, owner_id
FROM bookmarks_bookmarkbundle WHERE id = $1 AND owner_id = $2
''')
  Future<Result<BundleRow?, SqlxError>> owned(int id, int ownerId);

  /// The position after the last bundle: 0 when there is none.
  @Query(r'''
SELECT (COALESCE(MAX("order"), -1) + 1)::integer AS next
FROM bookmarks_bookmarkbundle WHERE owner_id = $1
''')
  Future<Result<int, SqlxError>> nextOrder(int ownerId);

  @Query(r'''
INSERT INTO bookmarks_bookmarkbundle (
  name, search, any_tags, all_tags, excluded_tags, "order", date_created,
  date_modified, owner_id, filter_shared, filter_unread)
VALUES ($1, $2, $3, $4, $5, $6, $7, $7, $8, $9, $10)
RETURNING id, name, search, any_tags, all_tags, excluded_tags, filter_unread,
          filter_shared, "order", date_created, date_modified, owner_id
''')
  Future<Result<BundleRow, SqlxError>> insert(
    String name,
    String search,
    String anyTags,
    String allTags,
    String excludedTags,
    int order,
    DateTime now,
    int ownerId,
    String filterShared,
    String filterUnread,
  );

  @Query(r'''
UPDATE bookmarks_bookmarkbundle SET
  name = $2, search = $3, any_tags = $4, all_tags = $5, excluded_tags = $6,
  "order" = $7, date_modified = $8, filter_shared = $9, filter_unread = $10
WHERE id = $1
RETURNING id, name, search, any_tags, all_tags, excluded_tags, filter_unread,
          filter_shared, "order", date_created, date_modified, owner_id
''')
  Future<Result<BundleRow, SqlxError>> update(
    int id,
    String name,
    String search,
    String anyTags,
    String allTags,
    String excludedTags,
    int order,
    DateTime now,
    String filterShared,
    String filterUnread,
  );

  @Query(r'''
DELETE FROM bookmarks_bookmarkbundle WHERE id = $1 AND owner_id = $2
''')
  Future<Result<Unit, SqlxError>> delete(int id, int ownerId);

  /// Renumbers the owner's bundles 0, 1, 2... in their current order, as
  /// linkding does after a delete. `date_modified` is left alone.
  @Query(r'''
UPDATE bookmarks_bookmarkbundle b SET "order" = r.position
FROM (
  SELECT id, (row_number() OVER (ORDER BY "order", id) - 1)::integer AS position
  FROM bookmarks_bookmarkbundle WHERE owner_id = $1
) r
WHERE b.id = r.id AND b."order" <> r.position
''')
  Future<Result<Unit, SqlxError>> renumber(int ownerId);

  @Query(r'''
UPDATE bookmarks_bookmarkbundle SET "order" = $2 WHERE id = $1
''')
  Future<Result<Unit, SqlxError>> setOrder(int id, int order);
}
