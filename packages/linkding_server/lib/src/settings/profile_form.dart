import '../compat/form_data.dart';
import '../db/rows/rows.dart';
import '../pages/support/cleaning.dart';

/// The choice fields of linkding's `UserProfileForm`, with their choices.
const profileChoices = {
  'theme': [('auto', 'Auto'), ('light', 'Light'), ('dark', 'Dark')],
  'bookmark_date_display': [
    ('relative', 'Relative'),
    ('absolute', 'Absolute'),
    ('hidden', 'Hidden'),
  ],
  'bookmark_description_display': [
    ('inline', 'Inline'),
    ('separate', 'Separate'),
  ],
  'bookmark_link_target': [('_blank', 'New page'), ('_self', 'Same page')],
  'web_archive_integration': [('disabled', 'Disabled'), ('enabled', 'Enabled')],
  'tag_search': [('strict', 'Strict'), ('lax', 'Lax')],
  'tag_grouping': [('alphabetical', 'Alphabetical'), ('disabled', 'Disabled')],
};

/// Its checkboxes.
const profileBooleans = [
  'enable_sharing',
  'enable_public_sharing',
  'enable_favicons',
  'enable_preview_images',
  'enable_automatic_html_snapshots',
  'display_url',
  'display_view_bookmark_action',
  'display_edit_bookmark_action',
  'display_archive_bookmark_action',
  'display_remove_bookmark_action',
  'permanent_notes',
  'default_mark_unread',
  'default_mark_shared',
  'sticky_pagination',
  'collapse_side_panel',
  'hide_bundles',
  'legacy_search',
];

/// linkding's `UserProfileForm`: what the fields show, and once submitted,
/// the values to save and the errors.
final class ProfileForm {
  ProfileForm(this.raw, this.booleans, {this.errors = const {}});

  /// The form for the saved profile [p].
  factory ProfileForm.of(ProfileRow p) => ProfileForm(
    {
      'theme': p.theme,
      'bookmark_date_display': p.bookmarkDateDisplay,
      'bookmark_description_display': p.bookmarkDescriptionDisplay,
      'bookmark_description_max_lines': '${p.bookmarkDescriptionMaxLines}',
      'bookmark_link_target': p.bookmarkLinkTarget,
      'web_archive_integration': p.webArchiveIntegration,
      'tag_search': p.tagSearch,
      'tag_grouping': p.tagGrouping,
      'custom_css': p.customCss,
      'auto_tagging_rules': p.autoTaggingRules,
      'items_per_page': '${p.itemsPerPage}',
    },
    {
      'enable_sharing': p.enableSharing,
      'enable_public_sharing': p.enablePublicSharing,
      'enable_favicons': p.enableFavicons,
      'enable_preview_images': p.enablePreviewImages,
      'enable_automatic_html_snapshots': p.enableAutomaticHtmlSnapshots,
      'display_url': p.displayUrl,
      'display_view_bookmark_action': p.displayViewBookmarkAction,
      'display_edit_bookmark_action': p.displayEditBookmarkAction,
      'display_archive_bookmark_action': p.displayArchiveBookmarkAction,
      'display_remove_bookmark_action': p.displayRemoveBookmarkAction,
      'permanent_notes': p.permanentNotes,
      'default_mark_unread': p.defaultMarkUnread,
      'default_mark_shared': p.defaultMarkShared,
      'sticky_pagination': p.stickyPagination,
      'collapse_side_panel': p.collapseSidePanel,
      'hide_bundles': p.hideBundles,
      'legacy_search': p.legacySearch,
    },
  );

  /// The submitted form, checked.
  factory ProfileForm.bound(FormData data) {
    final raw = <String, String?>{
      for (final name in [
        ...profileChoices.keys,
        'bookmark_description_max_lines',
        'items_per_page',
        'custom_css',
        'auto_tagging_rules',
      ])
        name: data[name],
    };
    final errors = <String, List<String>>{};
    for (final MapEntry(key: name, value: choices) in profileChoices.entries) {
      final value = raw[name] ?? '';
      if (value.isEmpty) {
        errors[name] = ['This field is required.'];
      } else if (!choices.any((c) => c.$1 == value)) {
        errors[name] = [
          'Select a valid choice. $value is not one of the available choices.',
        ];
      }
    }
    for (final (name, min) in const [
      ('bookmark_description_max_lines', null),
      ('items_per_page', 10),
    ]) {
      final problem = _integerError(raw[name], min);
      if (problem != null) errors[name] = [problem];
    }
    return ProfileForm(raw, {
      for (final name in profileBooleans) name: checkboxValue(data[name]),
    }, errors: errors);
  }

  /// What each non-checkbox field shows: the saved value, or what was sent.
  final Map<String, String?> raw;
  final Map<String, bool> booleans;
  final Map<String, List<String>> errors;

  bool get isValid => errors.isEmpty;

  bool checked(String name) => booleans[name] ?? false;

  /// An `IntegerField`'s value, once valid.
  int integer(String name) =>
      int.parse(raw[name]!.trim().replaceFirst(RegExp(r'\.0*\s*$'), ''));

  /// Django's `IntegerField`, then the model's limits.
  static String? _integerError(String? raw, int? min) {
    final text = (raw ?? '').trim().replaceFirst(RegExp(r'\.0*\s*$'), '');
    if (text.isEmpty) return 'This field is required.';
    final value = int.tryParse(text);
    if (value == null) return 'Enter a whole number.';
    if (min != null && value < min) {
      return 'Ensure this value is greater than or equal to $min.';
    }
    if (value < -2147483648) {
      return 'Ensure this value is greater than or equal to -2147483648.';
    }
    if (value > 2147483647) {
      return 'Ensure this value is less than or equal to 2147483647.';
    }
    return null;
  }
}
