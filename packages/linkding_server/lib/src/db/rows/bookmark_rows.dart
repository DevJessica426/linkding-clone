import 'package:dust_dart/db.dart';

part 'bookmark_rows.g.dart';

/// `bookmarks_bookmark`, without the columns linkding no longer reads.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class BookmarkRow {
  const BookmarkRow({
    required this.id,
    required this.url,
    required this.urlNormalized,
    required this.title,
    required this.description,
    required this.notes,
    required this.webArchiveSnapshotUrl,
    required this.faviconFile,
    required this.previewImageFile,
    required this.unread,
    required this.isArchived,
    required this.shared,
    required this.dateAdded,
    required this.dateModified,
    required this.ownerId,
    this.dateAccessed,
    this.latestSnapshotId,
  });

  final int id;
  final String url;
  final String urlNormalized;
  final String title;
  final String description;
  final String notes;
  final String webArchiveSnapshotUrl;
  final String faviconFile;
  final String previewImageFile;
  final bool unread;
  final bool isArchived;
  final bool shared;
  final DateTime dateAdded;
  final DateTime dateModified;
  final DateTime? dateAccessed;
  final int ownerId;
  final int? latestSnapshotId;
}

/// One tag on one bookmark, for filling in `tag_names` on a page of results.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class BookmarkTagRow {
  const BookmarkTagRow({
    required this.bookmarkId,
    required this.tagId,
    required this.name,
  });

  final int bookmarkId;
  final int tagId;
  final String name;
}

/// `bookmarks_bookmarkasset`: a snapshot or an uploaded file.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class AssetRow {
  const AssetRow({
    required this.id,
    required this.dateCreated,
    required this.file,
    required this.fileSize,
    required this.assetType,
    required this.contentType,
    required this.displayName,
    required this.status,
    required this.gzip,
    required this.bookmarkId,
  });

  final int id;
  final DateTime dateCreated;
  final String file;
  final int? fileSize;
  final String assetType;
  final String contentType;
  final String displayName;
  final String status;
  final bool gzip;
  final int bookmarkId;
}

/// One id.
@Derive([FromRow()])
final class IdRow {
  const IdRow({required this.id});

  final int id;
}

/// One stored file name.
@Derive([FromRow()])
final class FileRow {
  const FileRow({required this.file});

  final String file;
}
