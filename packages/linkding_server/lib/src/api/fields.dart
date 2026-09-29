// linkding's field checks: each endpoint reads its own fields with these,
// in the order DRF validates them, and reports every failure together.

import '../compat/django.dart';
import '../compat/python_values.dart';
import 'body.dart';
import 'errors.dart';

/// Thrown by the checks below: messages for one field, or for a list field,
/// messages by position.
final class FieldError implements Exception {
  const FieldError(this.detail);
  FieldError.message(String message) : detail = [message];
  final Object detail;
}

/// Collects field errors in the order fields are checked, which is the
/// order linkding reports them in.
final class FieldErrors {
  final errors = <String, Object>{};

  /// Runs [check] for [field], recording its error instead of throwing.
  T? check<T>(String field, T Function() check) {
    try {
      return check();
    } on FieldError catch (error) {
      errors[field] = error.detail;
      return null;
    }
  }

  void throwIfAny() {
    if (errors.isNotEmpty) throw ApiException.invalid(errors);
  }
}

/// What a request says about one field: absent, or a raw value (which may
/// be null). For forms, the last value of the key, with an unticked
/// checkbox meaning false.
({bool present, Object? value}) fieldOf(
  RequestBody body,
  String name, {
  required bool partial,
  bool checkbox = false,
  bool list = false,
}) {
  final form = body.form;
  if (form == null) {
    final json = body.json! as Map<String, Object?>;
    return json.containsKey(name)
        ? (present: true, value: json[name])
        : (present: false, value: null);
  }
  final values = form[name];
  if (values == null) {
    if (!partial && checkbox) return (present: true, value: false);
    return (present: false, value: null);
  }
  if (list) return (present: true, value: values);
  return (present: true, value: values.last);
}

/// A text field: numbers are accepted as text, surrounding whitespace is
/// trimmed, and then blank and length are checked, followed by any
/// [validators] (all of whose messages are reported together).
String text(
  Object? value, {
  bool allowBlank = false,
  int? maxLength,
  List<String? Function(String)> validators = const [],
}) {
  if (value == null) throw FieldError.message('This field may not be null.');
  if (value is bool || !(value is String || value is num)) {
    throw FieldError.message('Not a valid string.');
  }
  final trimmed = pythonStr(value).trim();
  if (trimmed.isEmpty) {
    if (!allowBlank) throw FieldError.message('This field may not be blank.');
    return '';
  }
  final errors = [
    for (final validator in validators) ?validator(trimmed),
    if (maxLength != null && trimmed.runes.length > maxLength)
      'Ensure this field has no more than $maxLength characters.',
  ];
  if (errors.isNotEmpty) throw FieldError(errors);
  return trimmed;
}

/// Django's URL validator, unless `LD_DISABLE_URL_VALIDATION` is set.
String? Function(String) validUrl({required bool disabled}) =>
    (value) => disabled || isValidUrl(value) ? null : 'Enter a valid URL.';

const _truthy = {
  't', 'T', 'y', 'Y', 'yes', 'Yes', 'YES', 'true', 'True', 'TRUE', //
  'on', 'On', 'ON', '1',
};
const _falsy = {
  'f', 'F', 'n', 'N', 'no', 'No', 'NO', 'false', 'False', 'FALSE', //
  'off', 'Off', 'OFF', '0',
};

/// A yes/no field, which also takes `1`, `"yes"`, `"on"` and the like.
bool boolean(Object? value) {
  if (value == null) throw FieldError.message('This field may not be null.');
  if (value == true || (value is num && value == 1)) return true;
  if (value == false || (value is num && value == 0)) return false;
  if (value is String && _truthy.contains(value)) return true;
  if (value is String && _falsy.contains(value)) return false;
  throw FieldError.message('Must be a valid boolean.');
}

/// A list of non-blank strings, with errors keyed by position.
List<String> stringList(Object? value) {
  if (value == null) throw FieldError.message('This field may not be null.');
  if (value is! List) {
    throw FieldError.message(
      'Expected a list of items but got type "${pythonTypeName(value)}".',
    );
  }
  final result = <String>[];
  final errors = <String, Object>{};
  for (final (index, item) in value.indexed) {
    try {
      result.add(text(item));
    } on FieldError catch (error) {
      errors['$index'] = error.detail;
    }
  }
  if (errors.isNotEmpty) throw FieldError(errors);
  return result;
}

/// An ISO 8601 date and time.
DateTime dateTime(Object? value) {
  if (value == null) throw FieldError.message('This field may not be null.');
  final parsed = parseDrfDateTime(value);
  if (parsed.error != null) throw FieldError.message(parsed.error!);
  return parsed.value!;
}

/// A whole number that fits a PostgreSQL `integer`; `"5"` and `5.0` count.
int integer(Object? value) {
  if (value == null) throw FieldError.message('This field may not be null.');
  if (value is String && value.length > 1000) {
    throw FieldError.message('String value too large.');
  }
  final digits = value is bool
      ? ''
      : pythonStr(value).replaceFirst(RegExp(r'\.0*\s*$'), '').trim();
  final parsed = RegExp(r'^[+-]?\d+(?:_\d+)*$').hasMatch(digits)
      ? int.tryParse(digits.replaceAll('_', ''))
      : null;
  if (parsed == null) throw FieldError.message('A valid integer is required.');
  if (parsed > 2147483647) {
    throw FieldError.message(
      'Ensure this value is less than or equal to 2147483647.',
    );
  }
  if (parsed < -2147483648) {
    throw FieldError.message(
      'Ensure this value is greater than or equal to -2147483648.',
    );
  }
  return parsed;
}

/// One of [choices].
String choice(Object? value, Set<String> choices) {
  if (value == null) throw FieldError.message('This field may not be null.');
  final chosen = pythonStr(value);
  if (choices.contains(chosen)) return chosen;
  throw FieldError.message('"$chosen" is not a valid choice.');
}
