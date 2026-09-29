import 'package:dust_dart/db.dart';

part 'tag_rows.g.dart';

/// `bookmarks_tag`.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class TagRow {
  const TagRow({
    required this.id,
    required this.name,
    required this.dateAdded,
    required this.ownerId,
  });

  final int id;
  final String name;
  final DateTime dateAdded;
  final int ownerId;
}

/// A tag with how many of the owner's bookmarks carry it, for the tags page.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class TagUsageRow {
  const TagUsageRow({
    required this.id,
    required this.name,
    required this.dateAdded,
    required this.bookmarkCount,
  });

  final int id;
  final String name;
  final DateTime dateAdded;
  final int bookmarkCount;
}
