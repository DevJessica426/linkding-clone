import '../db/rows.dart';
import '../web/forms.dart';
import '../web/html.dart';
import 'profile_form.dart';

/// A `FormSelect` with the attributes [fieldAttributes] built.
String selectWidget(
  String name,
  List<(String, String)> choices,
  String? selected,
  Map<String, Object> attrs,
) {
  final attributes = [
    for (final MapEntry(:key, :value) in attrs.entries)
      value == true ? ' $key' : ' $key="${e(value)}"',
  ].join();
  final options = [
    for (final (value, label) in choices)
      '  <option value="${e(value)}"${value == selected ? ' selected' : ''}>'
          '${e(label)}</option>\n',
  ].join('\n');
  return '<select name="$name"$attributes>\n$options\n</select>';
}

/// What `settings/general.html` reads for the profile form: each field's
/// widget (`w_<name>`), and the few classes and states around them.
Map<String, Object?> profileWidgetValues(ProfileForm f, ProfileRow saved) {
  Map<String, Object> attrs(
    String name, {
    Map<String, Object> widget = const {},
    bool required = false,
    bool hasHelp = false,
    Map<String, Object> extra = const {},
  }) => fieldAttributes(
    name,
    widget: widget,
    required: required,
    requiredAttribute: widget['class'] != 'form-select',
    hasHelp: hasHelp,
    errors: f.errors[name] ?? const [],
    extra: extra,
  );

  const narrow = 'width-25 width-sm-100';
  const helped = {
    'display_url',
    'permanent_notes',
    'sticky_pagination',
    'collapse_side_panel',
    'hide_bundles',
    'legacy_search',
    'enable_favicons',
    'enable_preview_images',
    'enable_sharing',
    'enable_public_sharing',
    'default_mark_unread',
    'default_mark_shared',
  };
  return {
    for (final MapEntry(key: name, value: choices) in profileChoices.entries)
      'w_$name': selectWidget(
        name,
        choices,
        f.raw[name],
        attrs(
          name,
          widget: const {'class': 'form-select'},
          required: true,
          hasHelp: true,
          extra: const {'class': narrow},
        ),
      ),
    for (final (name, min) in const [
      ('bookmark_description_max_lines', null),
      ('items_per_page', '10'),
    ])
      'w_$name': inputField(
        'number',
        name,
        f.raw[name],
        attrs(
          name,
          widget: const {'class': 'form-input'},
          required: true,
          hasHelp: true,
          extra: {'class': narrow, 'min': ?min},
        ),
      ),
    for (final name in profileBooleans)
      'w_$name': checkboxField(
        name,
        f.checked(name),
        _labels[name] ?? '',
        attrs(name, hasHelp: helped.contains(name)),
      ),
    for (final name in const ['auto_tagging_rules', 'custom_css']) ...{
      'w_$name': textareaField(
        name,
        f.raw[name],
        attrs(
          name,
          widget: const {'cols': '40', 'rows': '10', 'class': 'form-input'},
          hasHelp: true,
          extra: const {'class': 'monospace', 'rows': '6'},
        ),
      ),
      'open_$name': (f.raw[name] ?? '').isNotEmpty,
    },
    'maxLinesClass':
        'form-group '
        '${saved.bookmarkDescriptionDisplay == 'inline' ? 'd-hide' : ''}',
    'itemsPerPageErrors': errorList(
      'items_per_page',
      f.errors['items_per_page'] ?? const [],
      styled: false,
    ),
  };
}

const _labels = {
  'display_url': 'Show bookmark URL',
  'permanent_notes': 'Show notes permanently',
  'display_view_bookmark_action': 'View',
  'display_edit_bookmark_action': 'Edit',
  'display_archive_bookmark_action': 'Archive',
  'display_remove_bookmark_action': 'Remove',
  'sticky_pagination': 'Sticky pagination',
  'collapse_side_panel': 'Collapse side panel',
  'hide_bundles': 'Hide bundles',
  'legacy_search': 'Enable legacy search',
  'enable_favicons': 'Enable Favicons',
  'enable_preview_images': 'Enable Preview Images',
  'enable_sharing': 'Enable bookmark sharing',
  'enable_public_sharing': 'Enable public bookmark sharing',
  'default_mark_unread': 'Create bookmarks as unread by default',
  'default_mark_shared': 'Create bookmarks as shared by default',
};
