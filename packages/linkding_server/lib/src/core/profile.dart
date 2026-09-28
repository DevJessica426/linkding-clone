import 'dart:convert';

import '../db/rows.dart';

/// A user's preferences, read from `bookmarks_userprofile`.
extension type const Profile(ProfileRow row) {
  bool get laxTags => row.tagSearch == 'lax';
  bool get legacySearch => row.legacySearch;
  String get autoTaggingRules => row.autoTaggingRules;

  /// The saved sort and filters: `sort`, `shared` and `unread`, each only if
  /// the user saved one.
  Map<String, String> get searchPreferences {
    final decoded = jsonDecode(row.searchPreferencesJson);
    if (decoded is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (key is String && value is String) key: value,
    };
  }
}

/// The preferences of a visitor when no guest profile is set: a fresh
/// `UserProfile` with favicons enabled.
const standardProfile = ProfileRow(
  id: 0,
  userId: 0,
  theme: 'auto',
  bookmarkDateDisplay: 'relative',
  bookmarkDescriptionDisplay: 'inline',
  bookmarkDescriptionMaxLines: 1,
  bookmarkLinkTarget: '_blank',
  webArchiveIntegration: 'disabled',
  tagSearch: 'strict',
  tagGrouping: 'alphabetical',
  enableSharing: false,
  enablePublicSharing: false,
  enableFavicons: true,
  enablePreviewImages: false,
  displayUrl: false,
  displayViewBookmarkAction: true,
  displayEditBookmarkAction: true,
  displayArchiveBookmarkAction: true,
  displayRemoveBookmarkAction: true,
  permanentNotes: false,
  customCss: '',
  customCssHash: '',
  autoTaggingRules: '',
  searchPreferencesJson: '{}',
  enableAutomaticHtmlSnapshots: true,
  defaultMarkUnread: false,
  defaultMarkShared: false,
  itemsPerPage: 30,
  stickyPagination: false,
  collapseSidePanel: false,
  hideBundles: false,
  legacySearch: false,
);
