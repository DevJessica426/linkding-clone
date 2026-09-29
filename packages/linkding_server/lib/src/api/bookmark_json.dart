import 'package:dust_server/server.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../core/urls.dart';
import '../db/rows.dart';
import '../services/bookmarks.dart';
import 'lookups.dart';

/// linkding's `BookmarkSerializer` for [row] with its [tags].
Map<String, Object?> bookmarkJson(
  Request request,
  BookmarkRow row,
  List<String> tags,
) => Bookmark(
  id: row.id,
  url: row.url,
  title: row.title,
  description: row.description,
  notes: row.notes,
  webArchiveSnapshotUrl: row.webArchiveSnapshotUrl.isNotEmpty
      ? row.webArchiveSnapshotUrl
      : (row.url.isEmpty
            ? null
            : webArchiveFallbackUrl(row.url, row.dateAdded)),
  faviconUrl: row.faviconFile.isEmpty
      ? null
      : absoluteUrl(request, '/static/${row.faviconFile}'),
  previewImageUrl: row.previewImageFile.isEmpty
      ? null
      : absoluteUrl(request, '/static/${row.previewImageFile}'),
  isArchived: row.isArchived,
  unread: row.unread,
  shared: row.shared,
  tagNames: [...tags]..sort(),
  dateAdded: row.dateAdded,
  dateModified: row.dateModified,
).toJson();

/// [bookmarkJson] with the bookmark's tags looked up.
Future<Map<String, Object?>> serializeBookmark(
  Request request,
  BookmarkRow row,
) async {
  final tags = await (await request.state<BookmarkService>()).tagNames([
    row.id,
  ]);
  return bookmarkJson(request, row, tags[row.id] ?? const []);
}
