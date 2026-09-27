import 'package:dust_dart/db.dart';

import 'rows.dart';

part 'users_repo.g.dart';

/// Users, their profiles, API tokens, feed tokens and sessions.
@SqlxDao()
abstract final class UsersRepo {
  const factory UsersRepo(Executor db) = _$UsersRepo;

  /// Signing in: usernames are compared exactly, as Django does.
  @Query(r'''
SELECT id, password, last_login, is_superuser, username, first_name,
       last_name, email, is_staff, is_active, date_joined
FROM auth_user WHERE username = $1
''')
  Future<Result<UserRow?, SqlxError>> byUsername(String username);

  @Query(r'''
SELECT id, password, last_login, is_superuser, username, first_name,
       last_name, email, is_staff, is_active, date_joined
FROM auth_user WHERE id = $1
''')
  Future<Result<UserRow?, SqlxError>> byId(int id);

  /// The owner of an API token; the caller checks `is_active`.
  @Query(r'''
SELECT u.id, u.password, u.last_login, u.is_superuser, u.username,
       u.first_name, u.last_name, u.email, u.is_staff, u.is_active,
       u.date_joined
FROM bookmarks_apitoken t JOIN auth_user u ON u.id = t.user_id
WHERE t.key = $1
''')
  Future<Result<UserRow?, SqlxError>> byApiToken(String key);

  /// The owner of a session that has not expired.
  @Query(r'''
SELECT u.id, u.password, u.last_login, u.is_superuser, u.username,
       u.first_name, u.last_name, u.email, u.is_staff, u.is_active,
       u.date_joined
FROM clone_session s JOIN auth_user u ON u.id = s.user_id
WHERE s.session_key = $1 AND s.expire_date > $2
''')
  Future<Result<UserRow?, SqlxError>> bySession(String key, DateTime now);

  @Query(r'''
INSERT INTO auth_user (password, last_login, is_superuser, username,
                       first_name, last_name, email, is_staff, is_active,
                       date_joined)
VALUES ($1, NULL, $2, $3, '', '', $4, $2, true, $5)
RETURNING id, password, last_login, is_superuser, username, first_name,
          last_name, email, is_staff, is_active, date_joined
''')
  Future<Result<UserRow, SqlxError>> insert(
    String password,
    bool isSuperuser,
    String username,
    String email,
    DateTime dateJoined,
  );

  @Query(r'UPDATE auth_user SET password = $2 WHERE id = $1')
  Future<Result<Unit, SqlxError>> setPassword(int id, String password);

  @Query(r'UPDATE auth_user SET last_login = $2 WHERE id = $1')
  Future<Result<Unit, SqlxError>> setLastLogin(int id, DateTime at);

  @Query(
    r'SELECT id, username FROM auth_user WHERE is_active ORDER BY username',
  )
  Future<Result<List<UserNameRow>, SqlxError>> activeUsers();

  // --- Profiles ---

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

  // --- API tokens ---

  @Query(r'''
INSERT INTO bookmarks_apitoken (key, name, created, user_id)
VALUES ($1, $2, $3, $4)
RETURNING id, key, name, created, user_id
''')
  Future<Result<ApiTokenRow, SqlxError>> insertApiToken(
    String key,
    String name,
    DateTime created,
    int userId,
  );

  @Query(r'''
SELECT id, key, name, created, user_id FROM bookmarks_apitoken
WHERE user_id = $1 ORDER BY created DESC, id DESC
''')
  Future<Result<List<ApiTokenRow>, SqlxError>> apiTokens(int userId);

  @Query(r'DELETE FROM bookmarks_apitoken WHERE id = $1 AND user_id = $2')
  Future<Result<Unit, SqlxError>> deleteApiToken(int id, int userId);

  // --- Feed tokens ---

  @Query(r'SELECT key FROM bookmarks_feedtoken WHERE user_id = $1')
  Future<Result<String?, SqlxError>> feedToken(int userId);

  @Query(r'''
INSERT INTO bookmarks_feedtoken (key, created, user_id) VALUES ($1, $2, $3)
ON CONFLICT (user_id) DO NOTHING
''')
  Future<Result<Unit, SqlxError>> insertFeedToken(
    String key,
    DateTime created,
    int userId,
  );

  @Query(r'''
SELECT u.id, u.password, u.last_login, u.is_superuser, u.username,
       u.first_name, u.last_name, u.email, u.is_staff, u.is_active,
       u.date_joined
FROM bookmarks_feedtoken f JOIN auth_user u ON u.id = f.user_id
WHERE f.key = $1
''')
  Future<Result<UserRow?, SqlxError>> byFeedToken(String key);

  // --- Sessions ---

  @Query(r'''
INSERT INTO clone_session (session_key, user_id, expire_date)
VALUES ($1, $2, $3)
''')
  Future<Result<Unit, SqlxError>> insertSession(
    String key,
    int userId,
    DateTime expires,
  );

  @Query(r'DELETE FROM clone_session WHERE session_key = $1')
  Future<Result<Unit, SqlxError>> deleteSession(String key);

  /// Every session of a user but [keep], after a password change.
  @Query(r'DELETE FROM clone_session WHERE user_id = $1 AND session_key <> $2')
  Future<Result<Unit, SqlxError>> deleteOtherSessions(int userId, String keep);

  @Query(r'DELETE FROM clone_session WHERE expire_date <= $1')
  Future<Result<Unit, SqlxError>> deleteExpiredSessions(DateTime now);
}

/// A user's id and name, for the shared bookmarks filter.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class UserNameRow {
  const UserNameRow({required this.id, required this.username});

  final int id;
  final String username;
}
