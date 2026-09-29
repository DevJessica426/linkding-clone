import 'package:dust_dart/db.dart';

import '../rows/bookmark_rows.dart';

part 'bookmark_tags_repo.g.dart';

/// The tags on bookmarks: what a page shows, and linking and unlinking them.
@SqlxDao()
abstract final class BookmarkTagsRepo {
  const factory BookmarkTagsRepo(Executor db) = _$BookmarkTagsRepo;

  /// The tags of a page of bookmarks.
  @Query(r'''
SELECT bt.bookmark_id, t.id AS tag_id, t.name
FROM bookmarks_bookmark_tags bt JOIN bookmarks_tag t ON t.id = bt.tag_id
WHERE bt.bookmark_id = ANY($1)
ORDER BY t.id
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
}
