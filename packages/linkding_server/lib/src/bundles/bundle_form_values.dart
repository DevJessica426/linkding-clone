import '../pages/support/html.dart';
import '../pages/support/widgets.dart';
import 'bundle_fields.dart';

const _text = {
  'class': 'form-input',
  'autocomplete': 'off',
  'maxlength': '256',
};

/// What `bundle-form-fields` reads (`bundles/form.html`): the widgets as
/// Django renders them, with [errors] from a submitted form.
Map<String, Object?> bundleFormValues(
  BundleFields v,
  Map<String, List<String>> errors,
) {
  List<String> errorsOf(String name) => errors[name] ?? const [];
  Map<String, Object?> tagField(
    String name,
    String label,
    String value,
    String help,
  ) {
    final attrs = fieldAttributes(name, hasHelp: true, errors: errorsOf(name));
    return {
      'name': name,
      'label': label,
      'value': value,
      'describedBy': attrs['aria-describedby'],
      'hasClass': attrs['class'] != null,
      'classes': attrs['class'] ?? '',
      'help': help,
    };
  }

  Map<String, Object?> select(
    String name,
    String label,
    List<(String, String)> choices,
    String? value,
    String help,
  ) => {
    'name': name,
    'label': label,
    'widget': _select(name, choices, value, errorsOf(name)),
    'help': help,
  };

  return {
    'nameInput': inputField(
      'text',
      'name',
      v.rawName,
      fieldAttributes(
        'name',
        widget: _text,
        required: true,
        errors: errorsOf('name'),
      ),
    ),
    'nameErrors': errorList('name', errorsOf('name')),
    'searchInput': inputField(
      'text',
      'search',
      v.rawSearch,
      fieldAttributes(
        'search',
        widget: _text,
        hasHelp: true,
        errors: errorsOf('search'),
      ),
    ),
    'searchErrors': errorList('search', errorsOf('search')),
    'tagFields': [
      tagField(
        'any_tags',
        'Tags',
        v.rawAnyTags,
        'At least one of these tags must be present in a bookmark to match.',
      ),
      tagField(
        'all_tags',
        'Required tags',
        v.rawAllTags,
        'All of these tags must be present in a bookmark to match.',
      ),
      tagField(
        'excluded_tags',
        'Excluded tags',
        v.rawExcludedTags,
        'None of these tags must be present in a bookmark to match.',
      ),
    ],
    'selectFields': [
      select(
        'filter_unread',
        'Reading State',
        const [('off', 'All'), ('yes', 'Unread'), ('no', 'Read')],
        v.shownUnread,
        'Limit matches to unread or read bookmarks.',
      ),
      select(
        'filter_shared',
        'Sharing State',
        const [('off', 'All'), ('yes', 'Shared'), ('no', 'Unshared')],
        v.shownShared,
        'Limit matches to shared or unshared bookmarks.',
      ),
    ],
  };
}

/// A `Select` through linkding's `formfield` tag, with help and errors.
String _select(
  String name,
  List<(String, String)> choices,
  String? value,
  List<String> errors,
) {
  final attrs = fieldAttributes(
    name,
    widget: const {'class': 'form-select'},
    hasHelp: true,
    errors: errors,
  );
  final options = [
    for (final (choice, text) in choices)
      '  <option value="$choice"${choice == value ? ' selected' : ''}>'
          '$text</option>\n',
  ].join('\n');
  final attributes = [
    for (final MapEntry(key: k, value: a) in attrs.entries)
      a == true ? ' $k' : ' $k="${e(a)}"',
  ].join();
  return '<select name="$name"$attributes>\n$options\n</select>';
}
