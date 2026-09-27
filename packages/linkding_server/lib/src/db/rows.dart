import 'package:dust_dart/db.dart';

part 'rows.g.dart';

// What the queries select, one type per shape, over linkding's own tables.
// `dust build` writes the row mapping; `dust db build` checks every column
// against these fields.

/// `auth_user`, password hash included.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class UserRow {
  const UserRow({
    required this.id,
    required this.password,
    required this.isSuperuser,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.isStaff,
    required this.isActive,
    required this.dateJoined,
    this.lastLogin,
  });

  final int id;

  /// Django's `algorithm$iterations$salt$hash`.
  final String password;

  final DateTime? lastLogin;
  final bool isSuperuser;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final bool isStaff;
  final bool isActive;
  final DateTime dateJoined;
}

/// `bookmarks_userprofile`: every preference a user can set.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class ProfileRow {
  const ProfileRow({
    required this.id,
    required this.userId,
    required this.theme,
    required this.bookmarkDateDisplay,
    required this.bookmarkDescriptionDisplay,
    required this.bookmarkDescriptionMaxLines,
    required this.bookmarkLinkTarget,
    required this.webArchiveIntegration,
    required this.tagSearch,
    required this.tagGrouping,
    required this.enableSharing,
    required this.enablePublicSharing,
    required this.enableFavicons,
    required this.enablePreviewImages,
    required this.displayUrl,
    required this.displayViewBookmarkAction,
    required this.displayEditBookmarkAction,
    required this.displayArchiveBookmarkAction,
    required this.displayRemoveBookmarkAction,
    required this.permanentNotes,
    required this.customCss,
    required this.customCssHash,
    required this.autoTaggingRules,
    required this.searchPreferencesJson,
    required this.enableAutomaticHtmlSnapshots,
    required this.defaultMarkUnread,
    required this.defaultMarkShared,
    required this.itemsPerPage,
    required this.stickyPagination,
    required this.collapseSidePanel,
    required this.hideBundles,
    required this.legacySearch,
  });

  final int id;
  final int userId;
  final String theme;
  final String bookmarkDateDisplay;
  final String bookmarkDescriptionDisplay;
  final int bookmarkDescriptionMaxLines;
  final String bookmarkLinkTarget;
  final String webArchiveIntegration;
  final String tagSearch;
  final String tagGrouping;
  final bool enableSharing;
  final bool enablePublicSharing;
  final bool enableFavicons;
  final bool enablePreviewImages;
  final bool displayUrl;
  final bool displayViewBookmarkAction;
  final bool displayEditBookmarkAction;
  final bool displayArchiveBookmarkAction;
  final bool displayRemoveBookmarkAction;
  final bool permanentNotes;
  final String customCss;
  final String customCssHash;
  final String autoTaggingRules;

  /// `search_preferences`, a JSON object selected as text.
  final String searchPreferencesJson;

  final bool enableAutomaticHtmlSnapshots;
  final bool defaultMarkUnread;
  final bool defaultMarkShared;
  final int itemsPerPage;
  final bool stickyPagination;
  final bool collapseSidePanel;
  final bool hideBundles;
  final bool legacySearch;
}

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

/// `bookmarks_apitoken`.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class ApiTokenRow {
  const ApiTokenRow({
    required this.id,
    required this.key,
    required this.name,
    required this.created,
    required this.userId,
  });

  final int id;
  final String key;
  final String name;
  final DateTime created;
  final int userId;
}

/// `bookmarks_globalsettings`.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class GlobalSettingsRow {
  const GlobalSettingsRow({
    required this.id,
    required this.landingPage,
    required this.enableLinkPrefetch,
    this.guestProfileUserId,
  });

  final int id;
  final String landingPage;
  final int? guestProfileUserId;
  final bool enableLinkPrefetch;
}

/// `bookmarks_toast`.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class ToastRow {
  const ToastRow({
    required this.id,
    required this.key,
    required this.message,
    required this.acknowledged,
    required this.ownerId,
  });

  final int id;
  final String key;
  final String message;
  final bool acknowledged;
  final int ownerId;
}

// Dust DAOs return rows or a single value, not a list of plain values, so a
// one-column list needs a one-field row type.

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
