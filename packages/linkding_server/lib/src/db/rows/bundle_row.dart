import 'package:dust_dart/db.dart';

part 'bundle_row.g.dart';

/// `bookmarks_bookmarkbundle`.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class BundleRow {
  const BundleRow({
    required this.id,
    required this.name,
    required this.search,
    required this.anyTags,
    required this.allTags,
    required this.excludedTags,
    required this.filterUnread,
    required this.filterShared,
    required this.order,
    required this.dateCreated,
    required this.dateModified,
    required this.ownerId,
  });

  final int id;
  final String name;
  final String search;
  final String anyTags;
  final String allTags;
  final String excludedTags;
  final String filterUnread;
  final String filterShared;
  final int order;
  final DateTime dateCreated;
  final DateTime dateModified;
  final int ownerId;
}
