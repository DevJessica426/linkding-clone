import '../core/urls.dart';
import '../db/rows.dart';
import '../notes/markdown.dart';
import '../pages/format.dart';
import '../pages/html.dart' show q;
import '../pages/visitor.dart';
import '../services/search.dart';
import 'list_page.dart';

/// What `bookmark-item` reads for one bookmark of the list: linkding's
/// `BookmarkItem`.
Map<String, Object?> itemValues(
  Visitor visitor,
  ListPage p,
  Candidate candidate,
) {
  final profile = visitor.profile.row;
  final b = candidate.row;
  final links = p.links;
  final isEditable = b.ownerId == visitor.user?.id;
  final tags = [...candidate.tags]..sort();
  final classes = [if (b.unread) 'unread', if (b.shared) 'shared'].join(' ');
  final date = switch (profile.bookmarkDateDisplay) {
    'relative' => humanizeRelativeDate(b.dateAdded),
    'absolute' => humanizeAbsoluteDate(b.dateAdded),
    _ => null,
  };
  final (snapshotUrl, snapshotTitle) = _snapshot(b);
  final owner = p.owners[b.ownerId] ?? '';
  final notesButton = b.notes.isNotEmpty && !profile.permanentNotes;
  final markAsRead = isEditable && b.unread;
  final unshare = isEditable && b.shared && profile.enableSharing;
  return {
    'id': b.id,
    'hasClasses': classes.isNotEmpty,
    'classes': classes,
    'url': b.url,
    'title': b.title.isNotEmpty ? b.title : b.url,
    'hasFavicon': b.faviconFile.isNotEmpty && profile.enableFavicons,
    'favicon': '/static/${b.faviconFile}',
    'hasTags': tags.isNotEmpty,
    'tags': [
      for (final tag in tags) {'name': tag, 'query': links.addTag(tag)},
    ],
    'tagsAndDescription': tags.isNotEmpty && b.description.isNotEmpty,
    'hasDescription': b.description.isNotEmpty,
    'description': b.description,
    'hasNotes': b.notes.isNotEmpty,
    'notes': b.notes.isEmpty ? '' : renderNotes(b.notes),
    'hasDate': date != null,
    'date': date ?? '',
    'hasSnapshot': snapshotUrl.isNotEmpty,
    'snapshotUrl': snapshotUrl,
    'snapshotTitle': snapshotTitle,
    'detailsUrl': links.details(b.id),
    'isEditable': isEditable,
    'isArchived': b.isArchived,
    'returnUrl': q(links.index()),
    'owner': owner,
    'ownerQuery': (p.query.copy()..['user'] = owner).encode(),
    'hasExtraActions': notesButton || markAsRead || unshare,
    'markAsRead': markAsRead,
    'unshare': unshare,
    'notesButton': notesButton,
    'hasPreviewImage': b.previewImageFile.isNotEmpty,
    'previewImage': '/static/${b.previewImageFile}',
  };
}

/// Where the date links to: the latest snapshot, else the Internet
/// Archive's copy.
(String, String) _snapshot(BookmarkRow b) {
  if (b.latestSnapshotId case final id?) {
    return ('/assets/$id', 'View latest snapshot');
  }
  final url = b.webArchiveSnapshotUrl.isNotEmpty
      ? b.webArchiveSnapshotUrl
      : webArchiveFallbackUrl(b.url, b.dateAdded);
  return (url, 'View snapshot on the Internet Archive Wayback Machine');
}
