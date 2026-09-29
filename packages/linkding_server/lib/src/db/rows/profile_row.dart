import 'package:dust_dart/db.dart';

part 'profile_row.g.dart';

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
