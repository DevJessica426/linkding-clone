import 'package:dust_dart/db.dart';

import '../rows/profile_row.dart';

part 'profiles_repo.g.dart';

/// The preferences of each user, in `bookmarks_userprofile`.
@SqlxDao()
abstract final class ProfilesRepo {
  const factory ProfilesRepo(Executor db) = _$ProfilesRepo;

  @Query(r'''
SELECT id, user_id, theme, bookmark_date_display, bookmark_description_display,
       bookmark_description_max_lines, bookmark_link_target,
       web_archive_integration, tag_search, tag_grouping, enable_sharing,
       enable_public_sharing, enable_favicons, enable_preview_images,
       display_url, display_view_bookmark_action, display_edit_bookmark_action,
       display_archive_bookmark_action, display_remove_bookmark_action,
       permanent_notes, custom_css, custom_css_hash, auto_tagging_rules,
       search_preferences::text AS search_preferences_json,
       enable_automatic_html_snapshots, default_mark_unread,
       default_mark_shared, items_per_page, sticky_pagination,
       collapse_side_panel, hide_bundles, legacy_search
FROM bookmarks_userprofile WHERE user_id = $1
''')
  Future<Result<ProfileRow?, SqlxError>> profile(int userId);

  /// A new user's profile with linkding's defaults, written out because
  /// Django keeps none in the database.
  @Query(r'''
INSERT INTO bookmarks_userprofile (
  user_id, theme, bookmark_date_display, bookmark_link_target,
  web_archive_integration, enable_sharing, enable_favicons, tag_search,
  display_url, permanent_notes, enable_public_sharing, search_preferences,
  custom_css, bookmark_description_display, bookmark_description_max_lines,
  display_archive_bookmark_action, display_edit_bookmark_action,
  display_remove_bookmark_action, display_view_bookmark_action,
  enable_automatic_html_snapshots, default_mark_unread, enable_preview_images,
  tag_grouping, auto_tagging_rules, items_per_page, sticky_pagination,
  custom_css_hash, collapse_side_panel, hide_bundles, default_mark_shared,
  legacy_search)
VALUES (
  $1, 'auto', 'relative', '_blank',
  'disabled', false, false, 'strict',
  false, false, false, '{}'::jsonb,
  '', 'inline', 1,
  true, true,
  true, true,
  true, false, false,
  'alphabetical', '', 30, false,
  '', false, false, false,
  false)
ON CONFLICT (user_id) DO NOTHING
''')
  Future<Result<Unit, SqlxError>> insertDefaultProfile(int userId);

  /// Saves the general settings page.
  @Query(r'''
UPDATE bookmarks_userprofile SET
  theme = $2, bookmark_date_display = $3, bookmark_description_display = $4,
  bookmark_description_max_lines = $5, bookmark_link_target = $6,
  web_archive_integration = $7, tag_search = $8, tag_grouping = $9,
  enable_sharing = $10, enable_public_sharing = $11, enable_favicons = $12,
  enable_preview_images = $13, display_url = $14,
  display_view_bookmark_action = $15, display_edit_bookmark_action = $16,
  display_archive_bookmark_action = $17, display_remove_bookmark_action = $18,
  permanent_notes = $19, custom_css = $20, custom_css_hash = $21,
  auto_tagging_rules = $22, enable_automatic_html_snapshots = $23,
  default_mark_unread = $24, default_mark_shared = $25, items_per_page = $26,
  sticky_pagination = $27, collapse_side_panel = $28, hide_bundles = $29,
  legacy_search = $30
WHERE user_id = $1
''')
  Future<Result<Unit, SqlxError>> updateProfile(
    int userId,
    String theme,
    String bookmarkDateDisplay,
    String bookmarkDescriptionDisplay,
    int bookmarkDescriptionMaxLines,
    String bookmarkLinkTarget,
    String webArchiveIntegration,
    String tagSearch,
    String tagGrouping,
    bool enableSharing,
    bool enablePublicSharing,
    bool enableFavicons,
    bool enablePreviewImages,
    bool displayUrl,
    bool displayViewBookmarkAction,
    bool displayEditBookmarkAction,
    bool displayArchiveBookmarkAction,
    bool displayRemoveBookmarkAction,
    bool permanentNotes,
    String customCss,
    String customCssHash,
    String autoTaggingRules,
    bool enableAutomaticHtmlSnapshots,
    bool defaultMarkUnread,
    bool defaultMarkShared,
    int itemsPerPage,
    bool stickyPagination,
    bool collapseSidePanel,
    bool hideBundles,
    bool legacySearch,
  );

  /// Saves the sort and filters a user chose as their defaults.
  @Query(r'''
UPDATE bookmarks_userprofile SET search_preferences = $2::jsonb
WHERE user_id = $1
''')
  Future<Result<Unit, SqlxError>> setSearchPreferences(int userId, String json);

  @Query(r'''
UPDATE bookmarks_userprofile SET collapse_side_panel = $2 WHERE user_id = $1
''')
  Future<Result<Unit, SqlxError>> setCollapseSidePanel(int userId, bool value);
}
