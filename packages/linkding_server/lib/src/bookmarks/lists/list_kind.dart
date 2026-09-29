import '../../search/search.dart';

/// One of the three lists, with its addresses and texts.
enum ListKind {
  active(BookmarkList.active, '/bookmarks', 'Bookmarks', '', 'bulk_unarchive'),
  archived(
    BookmarkList.archived,
    '/bookmarks/archived',
    'Archived bookmarks',
    'archived',
    'bulk_archive',
  ),
  shared(
    BookmarkList.shared,
    '/bookmarks/shared',
    'Shared bookmarks',
    'shared',
    '',
  );

  const ListKind(
    this.list,
    this.indexUrl,
    this.title,
    this.searchMode,
    this.disabledBulkAction,
  );

  final BookmarkList list;
  final String indexUrl;
  final String title;
  final String searchMode;
  final String disabledBulkAction;

  String get actionUrl => '$indexUrl/action';
  bool get bulkEdit => this != shared;
}
