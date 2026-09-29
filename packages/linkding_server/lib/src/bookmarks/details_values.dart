import 'package:dust_server/server.dart';

import '../core/urls.dart';
import '../db/rows.dart';
import '../notes/markdown.dart';
import '../pages/format.dart';
import '../pages/html.dart' show q;
import '../pages/render.dart';
import '../pages/visitor.dart';
import 'asset_icons.dart';
import 'list_page.dart';

/// `bookmarks/details/modal.html`, or the empty frame without details.
String renderDetails(TemplateEngine engine, Visitor visitor, ListPage p) =>
    engine.render('bookmarks/details', {
      ...commonValues(visitor),
      'details': p.details == null ? false : _details(visitor, p, p.details!),
    });

Map<String, Object?> _details(Visitor visitor, ListPage p, Details d) {
  final b = d.bookmark;
  final profile = visitor.profile.row;
  final links = p.links;
  final archiveUrl = b.webArchiveSnapshotUrl.isNotEmpty
      ? b.webArchiveSnapshotUrl
      : webArchiveFallbackUrl(b.url, b.dateAdded);
  final snapshot = d.assets
      .where((a) => a.assetType == 'snapshot' && a.status == 'complete')
      .firstOrNull;
  return {
    'id': b.id,
    'title': b.title.isNotEmpty ? b.title : b.url,
    'closeUrl': links.index(),
    'isEditable': d.isEditable,
    'editReturnUrl': q(links.details(b.id)),
    'actionUrl': links.action(),
    'formAction': links.action({'details': '${b.id}'}),
    'url': b.url,
    'target': profile.bookmarkLinkTarget,
    'showIcons': profile.enableFavicons && b.faviconFile.isNotEmpty,
    'favicon': '/static/${b.faviconFile}',
    'hasSnapshot': snapshot != null,
    'snapshotId': snapshot?.id ?? 0,
    'hasArchiveUrl': archiveUrl.isNotEmpty,
    'archiveUrl': archiveUrl,
    'hasPreviewImage':
        profile.enablePreviewImages && b.previewImageFile.isNotEmpty,
    'previewImage': '/static/${b.previewImageFile}',
    'statusBoxes': [
      {'name': 'is_archived', 'label': 'Archived', 'checked': b.isArchived},
      {'name': 'unread', 'label': 'Unread', 'checked': b.unread},
      if (profile.enableSharing)
        {'name': 'shared', 'label': 'Shared', 'checked': b.shared},
    ],
    'hasAssets': d.assets.isNotEmpty,
    'assets': [for (final asset in d.assets) _asset(asset)],
    'uploadsEnabled': d.uploadsEnabled,
    'hasTags': d.tags.isNotEmpty,
    'tags': [
      for (final tag in d.tags) {'name': tag, 'query': links.addTag(tag)},
    ],
    'dateAdded': djangoDateTime(b.dateAdded),
    'hasDescription': b.description.isNotEmpty,
    'description': b.description,
    'hasNotes': b.notes.isNotEmpty,
    'notes': b.notes.isEmpty ? '' : renderNotes(b.notes),
  };
}

/// One file of `bookmarks/details/assets.html`.
Map<String, Object?> _asset(AssetRow asset) => {
  'id': asset.id,
  'iconClass': switch (asset.status) {
    'pending' => 'text-tertiary',
    'failure' => 'text-error',
    _ => 'icon-color',
  },
  'textClass': switch (asset.status) {
    'pending' => 'text-tertiary',
    'failure' => 'text-error',
    _ => '',
  },
  'icon': assetIcon(asset.contentType),
  'name': asset.displayName,
  'pending': asset.status == 'pending',
  'failed': asset.status == 'failure',
  'hasSize': (asset.fileSize ?? 0) != 0,
  'size': fileSize(asset.fileSize ?? 0),
  'hasFile': asset.file.isNotEmpty,
};
