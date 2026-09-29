import '../pages/html.dart' show q;
import '../pages/visitor.dart';
import '../pages/widgets.dart';
import 'list_page.dart';
import 'search_params.dart';
import 'search_values.dart';

/// What `bookmarks/page` reads (`bookmarks/bookmark_page.html`), around
/// the already rendered [list] and [tagCloud].
Map<String, Object?> pageValues(
  Visitor visitor,
  ListPage p, {
  required String list,
  required String tagCloud,
}) {
  final kind = p.kind;
  final profile = visitor.profile.row;
  return {
    'heading': kind.title,
    'bulkEdit': kind.bulkEdit,
    'collapseSidePanel': profile.collapseSidePanel,
    'signedIn': visitor.isAuthenticated,
    'search': searchValues(visitor, p),
    'actionUrl': p.links.action(),
    'bulkActions': _bulkActions(visitor, p),
    'total': p.page.total,
    'list': list,
    'bundleSection': _bundles(visitor, p) ?? false,
    'userSection': _users(p) ?? false,
    'tagCloud': tagCloud,
  };
}

/// The bulk edit bar's actions, less the one that makes no sense for the
/// list.
List<Map<String, String>> _bulkActions(Visitor visitor, ListPage p) {
  final disabled = p.kind.disabledBulkAction;
  final sharing = visitor.profile.row.enableSharing;
  return [
    for (final (value, label) in [
      if (disabled != 'bulk_archive') ('bulk_archive', 'Archive'),
      if (disabled != 'bulk_unarchive') ('bulk_unarchive', 'Unarchive'),
      ('bulk_delete', 'Delete'),
      ('bulk_tag', 'Add tags'),
      ('bulk_untag', 'Remove tags'),
      ('bulk_read', 'Mark as read'),
      ('bulk_unread', 'Mark as unread'),
      if (sharing) ('bulk_share', 'Share'),
      if (sharing) ('bulk_unshare', 'Unshare'),
      ('bulk_refresh', 'Refresh from website'),
    ])
      {'value': value, 'label': label},
  ];
}

/// `bookmarks/bundle_section.html`, unless there are no bundles or the
/// user hides them.
Map<String, Object?>? _bundles(Visitor visitor, ListPage p) {
  final bundles = p.bundles ?? const [];
  if (bundles.isEmpty || visitor.profile.row.hideBundles) return null;
  return {
    'hasQuery': p.search.q.isNotEmpty,
    'query': q(p.search.q),
    'items': [
      for (final bundle in bundles)
        {
          'id': bundle.id,
          'name': bundle.name,
          'selected': bundle.id == p.selectedBundleId,
        },
    ],
  };
}

/// `bookmarks/user_section.html`, on the shared page.
Map<String, Object?>? _users(ListPage p) {
  final users = p.users;
  if (users == null) return null;
  final choices = users.isEmpty
      ? const <(String, String)>[]
      : [('', 'Everyone'), for (final u in users) (u, u)];
  return {
    'userHidden': hiddenFields(p.search, const {'user'}),
    'userSelect': selectField(
      'user',
      choices,
      p.search.user,
      attributes: const {'data-submit-on-change': ''},
      ariaInvalid: false,
    ),
  };
}
