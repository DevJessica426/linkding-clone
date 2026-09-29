// Django's form field cleaning, as linkding's forms rely on it.

/// Django's `CharField` cleaning: surrounding whitespace dropped, null
/// characters and over-long values refused.
({String value, List<String> errors}) cleanChar(
  String? raw, {
  bool required = false,
  int? maxLength,
}) {
  final value = (raw ?? '').trim();
  if (value.contains('\x00')) {
    return (value: value, errors: const ['Null characters are not allowed.']);
  }
  if (value.isEmpty) {
    return (
      value: '',
      errors: required ? const ['This field is required.'] : const [],
    );
  }
  final length = value.runes.length;
  if (maxLength != null && length > maxLength) {
    return (
      value: value,
      errors: [
        'Ensure this value has at most $maxLength '
            'character${maxLength == 1 ? '' : 's'} (it has $length).',
      ],
    );
  }
  return (value: value, errors: const []);
}

/// Django's `CheckboxInput.value_from_datadict`: missing is unticked,
/// `true` and `false` (any case) are themselves, and any other non-empty
/// value, `0` included, is ticked.
bool checkboxValue(String? raw) => switch (raw?.toLowerCase()) {
  null || '' || 'false' => false,
  _ => true,
};
