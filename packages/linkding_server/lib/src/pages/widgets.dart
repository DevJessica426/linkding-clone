import 'html.dart';

// Django's form widgets, as linkding's templates render them.

/// `HiddenInput`: `<input type="hidden" name="q" value="x" id="id_q">`.
String hiddenInput(String name, Object? value) =>
    '<input type="hidden" name="$name"'
    '${value == null ? '' : ' value="${e(value)}"'} id="id_$name">';

/// `FormSelect` through linkding's `formfield` tag.
String selectField(
  String name,
  List<(String, String)> choices,
  String? selected, {
  String classes = 'form-select',
  Map<String, String> attributes = const {},
  bool ariaInvalid = true,
}) {
  final options = [
    for (final (value, label) in choices)
      '  <option value="${e(value)}"${value == selected ? ' selected' : ''}>'
          '${e(label)}</option>\n',
  ].join('\n');
  final extra = [
    for (final MapEntry(:key, :value) in attributes.entries)
      ' $key="${e(value)}"',
  ].join();
  return '<select name="$name" class="$classes"'
      '${ariaInvalid ? ' aria-invalid="false"' : ''}$extra id="id_$name">\n'
      '$options\n</select>';
}

/// One radio button of a `RadioSelect`: `{{ radio.tag }}`.
String radioInput(String name, int index, String value, bool checked) =>
    '<input type="radio" name="$name" value="${e(value)}" '
    'id="id_${name}_$index" required${checked ? ' checked' : ''}>';

/// A field's attributes as linkding's `formfield` tag and Django's
/// `BoundField.as_widget` build them: the widget's own, then help and error
/// references, `aria-invalid`, the tag's extra attributes, `required` and
/// the id. A value of `true` is an attribute without a value. A select
/// whose first option has a value gets no `required` attribute
/// ([requiredAttribute] false), as Django leaves it off. A field with a
/// Django `help_text` ([djangoHelpText]) refers to it unless the tag
/// already set a reference.
Map<String, Object> fieldAttributes(
  String name, {
  Map<String, Object> widget = const {},
  bool required = false,
  bool requiredAttribute = true,
  bool hasHelp = false,
  bool djangoHelpText = false,
  List<String> errors = const [],
  Map<String, Object> extra = const {},
}) {
  final attrs = <String, Object>{...widget};
  void append(String key, String value) =>
      attrs[key] = attrs[key] == null ? value : '${attrs[key]} $value';
  if (hasHelp) append('aria-describedby', 'id_${name}_help');
  if (errors.isNotEmpty) {
    append('class', 'is-error');
    append('aria-describedby', 'id_${name}_error');
  }
  if (required && errors.isEmpty) append('aria-invalid', 'false');
  extra.forEach(
    (key, value) =>
        key == 'class' ? append(key, value as String) : attrs[key] = value,
  );
  if (required && requiredAttribute) attrs['required'] = true;
  if (errors.isNotEmpty) attrs['aria-invalid'] = 'true';
  if (djangoHelpText && !attrs.containsKey('aria-describedby')) {
    attrs['aria-describedby'] = 'id_${name}_helptext';
  }
  attrs['id'] = 'id_$name';
  return attrs;
}

String _attributes(Map<String, Object> attrs) => [
  for (final MapEntry(:key, :value) in attrs.entries)
    value == true ? ' $key' : ' $key="${e(value)}"',
].join();

/// `TextInput` and friends: no `value` attribute for an empty value.
String inputField(
  String type,
  String name,
  String? value,
  Map<String, Object> attrs,
) =>
    '<input type="$type" name="$name"'
    '${value == null || value.isEmpty ? '' : ' value="${e(value)}"'}'
    '${_attributes(attrs)}>';

/// `Textarea`: its content starts on a new line, as Django writes it.
String textareaField(String name, String? value, Map<String, Object> attrs) =>
    '<textarea name="$name"${_attributes(attrs)}>\n${e(value ?? '')}</textarea>';

/// linkding's `FormCheckbox`, with its label beside the box.
String checkboxField(
  String name,
  bool checked,
  String label,
  Map<String, Object> attrs,
) =>
    '<div class="form-checkbox"><input type="checkbox" name="$name"'
    '${_attributes(attrs)}${checked ? ' checked' : ''}>'
    '<i class="form-icon"></i><label for="id_$name">${e(label)}</label></div>';

/// `{{ form.field.errors }}` through linkding's `shared/error_list.html`,
/// or Django's own list for a form without linkding's error class.
String errorList(String name, List<String> errors, {bool styled = true}) =>
    errors.isEmpty
    ? ''
    : '<ul class="errorlist${styled ? ' form-input-hint is-error' : ''}" '
          'id="id_${name}_error">'
          '${errors.map((m) => '<li>${e(m)}</li>').join()}</ul>';

/// Non-field errors: the same list without an id.
String formErrors(List<String> errors) => errors.isEmpty
    ? ''
    : '<ul class="errorlist nonfield form-input-hint is-error">'
          '${errors.map((m) => '<li>${e(m)}</li>').join()}</ul>';

/// `{% formhelp %}`.
String fieldHelp(String name, String html) =>
    '<div id="id_${name}_help" class="form-input-hint">$html</div>';

/// `{% formlabel %}`.
String fieldLabel(String name, String text) =>
    '<label for="id_$name" class="form-label">$text</label>';
