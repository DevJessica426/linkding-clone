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
