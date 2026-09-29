import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dust_dart/db.dart';

import '../db/or_throw.dart';
import '../db/repos/profiles_repo.dart';
import '../db/rows/rows.dart';
import 'profile_form.dart';

/// Saving a valid [ProfileForm], and applying an invalid one.
extension ProfileSaving on ProfileForm {
  /// [saved] with every field that passed its checks set to the submitted
  /// value, as Django's `construct_instance` leaves the profile of an
  /// invalid form. The CSS hash is only computed on saving.
  ProfileRow applyTo(ProfileRow saved) {
    String choice(String name, String current) =>
        errors.containsKey(name) ? current : raw[name]!;
    int number(String name, int current) =>
        errors.containsKey(name) ? current : integer(name);
    return ProfileRow(
      id: saved.id,
      userId: saved.userId,
      theme: choice('theme', saved.theme),
      bookmarkDateDisplay: choice(
        'bookmark_date_display',
        saved.bookmarkDateDisplay,
      ),
      bookmarkDescriptionDisplay: choice(
        'bookmark_description_display',
        saved.bookmarkDescriptionDisplay,
      ),
      bookmarkDescriptionMaxLines: number(
        'bookmark_description_max_lines',
        saved.bookmarkDescriptionMaxLines,
      ),
      bookmarkLinkTarget: choice(
        'bookmark_link_target',
        saved.bookmarkLinkTarget,
      ),
      webArchiveIntegration: choice(
        'web_archive_integration',
        saved.webArchiveIntegration,
      ),
      tagSearch: choice('tag_search', saved.tagSearch),
      tagGrouping: choice('tag_grouping', saved.tagGrouping),
      enableSharing: checked('enable_sharing'),
      enablePublicSharing: checked('enable_public_sharing'),
      enableFavicons: checked('enable_favicons'),
      enablePreviewImages: checked('enable_preview_images'),
      displayUrl: checked('display_url'),
      displayViewBookmarkAction: checked('display_view_bookmark_action'),
      displayEditBookmarkAction: checked('display_edit_bookmark_action'),
      displayArchiveBookmarkAction: checked('display_archive_bookmark_action'),
      displayRemoveBookmarkAction: checked('display_remove_bookmark_action'),
      permanentNotes: checked('permanent_notes'),
      customCss: (raw['custom_css'] ?? '').trim(),
      customCssHash: saved.customCssHash,
      autoTaggingRules: (raw['auto_tagging_rules'] ?? '').trim(),
      searchPreferencesJson: saved.searchPreferencesJson,
      enableAutomaticHtmlSnapshots: checked('enable_automatic_html_snapshots'),
      defaultMarkUnread: checked('default_mark_unread'),
      defaultMarkShared: checked('default_mark_shared'),
      itemsPerPage: number('items_per_page', saved.itemsPerPage),
      stickyPagination: checked('sticky_pagination'),
      collapseSidePanel: checked('collapse_side_panel'),
      hideBundles: checked('hide_bundles'),
      legacySearch: checked('legacy_search'),
    );
  }

  /// Writes the valid form to [userId]'s profile, with the custom CSS's
  /// hash for the pages to link it by.
  Future<void> save(Executor db, int userId) async {
    final css = (raw['custom_css'] ?? '').trim();
    (await ProfilesRepo(db).updateProfile(
      userId,
      raw['theme']!,
      raw['bookmark_date_display']!,
      raw['bookmark_description_display']!,
      integer('bookmark_description_max_lines'),
      raw['bookmark_link_target']!,
      raw['web_archive_integration']!,
      raw['tag_search']!,
      raw['tag_grouping']!,
      checked('enable_sharing'),
      checked('enable_public_sharing'),
      checked('enable_favicons'),
      checked('enable_preview_images'),
      checked('display_url'),
      checked('display_view_bookmark_action'),
      checked('display_edit_bookmark_action'),
      checked('display_archive_bookmark_action'),
      checked('display_remove_bookmark_action'),
      checked('permanent_notes'),
      css,
      css.isEmpty ? '' : md5.convert(utf8.encode(css)).toString(),
      (raw['auto_tagging_rules'] ?? '').trim(),
      checked('enable_automatic_html_snapshots'),
      checked('default_mark_unread'),
      checked('default_mark_shared'),
      integer('items_per_page'),
      checked('sticky_pagination'),
      checked('collapse_side_panel'),
      checked('hide_bundles'),
      checked('legacy_search'),
    )).orThrow;
  }
}
