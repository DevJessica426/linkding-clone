/// Reading API requests and writing API responses the way linkding's REST
/// API does: its error bodies, which bodies it accepts, and its validation
/// messages. Each endpoint checks its own fields with the small functions
/// here; nothing is generic beyond that.
library;

import 'dart:convert';

import 'package:dust_server/server.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../compat/django.dart';
import '../compat/form_data.dart';
import '../compat/pyurl.dart';

/// A JSON response as linkding sends it: compact UTF-8.
Response apiJson(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: body == null ? null : jsonEncode(body),
  headers: {'content-type': 'application/json', ...headers},
);

/// A failed API request, answered with its status and JSON body.
final class ApiException implements Exception {
  const ApiException(this.status, this.body, {this.headers = const {}});

  ApiException.detail(
    int status,
    String detail, {
    Map<String, String> headers = const {},
  }) : this(status, {'detail': detail}, headers: headers);

  static const _challenge = {'www-authenticate': 'Token'};

  static final notAuthenticated = ApiException.detail(
    401,
    'Authentication credentials were not provided.',
    headers: _challenge,
  );

  static ApiException authenticationFailed(String detail) =>
      ApiException.detail(401, detail, headers: _challenge);

  /// 404 for an id that exists nowhere, naming the model as Django does.
  static ApiException noMatch(String model) =>
      ApiException.detail(404, 'No $model matches the given query.');

  /// 404 for an id that is not a number at all.
  static final notFound = ApiException.detail(404, 'Not found.');

  static ApiException methodNotAllowed(String method, List<String> allowed) =>
      ApiException.detail(
        405,
        'Method "$method" not allowed.',
        headers: {'allow': allowed.join(', ')},
      );

  /// 400 with messages by field name.
  static ApiException invalid(Map<String, Object> errors) =>
      ApiException(400, errors);

  final int status;
  final Object body;
  final Map<String, String> headers;

  Response toResponse() => apiJson(body, status: status, headers: headers);
}

/// A request body: a JSON value, or form fields where a key can repeat.
final class RequestBody {
  const RequestBody.json(this.json) : form = null, files = const {};
  const RequestBody.form(this.form, [this.files = const {}]) : json = null;

  final Object? json;
  final Map<String, List<String>>? form;

  /// The files of a multipart body: `request.FILES`.
  final Map<String, FormFile> files;

  bool get isForm => form != null;
}

/// Reads the body. JSON, urlencoded and multipart forms are accepted; no
/// body at all counts as an empty object; anything else is a 415.
Future<RequestBody> readRequestBody(Request request) async {
  final bytes = await request.read().fold<List<int>>(
    [],
    (all, chunk) => all..addAll(chunk),
  );
  final contentType = request.headers['content-type'];
  final media = contentType?.split(';').first.trim().toLowerCase();
  if (bytes.isEmpty || contentType == null) {
    return media == 'application/x-www-form-urlencoded' ||
            media == 'multipart/form-data'
        ? const RequestBody.form({})
        : const RequestBody.json(<String, Object?>{});
  }
  switch (media) {
    case 'application/json':
      try {
        return RequestBody.json(jsonDecode(utf8.decode(bytes)));
      } on FormatException catch (error) {
        throw ApiException.detail(400, 'JSON parse error - ${error.message}');
      }
    case 'application/x-www-form-urlencoded':
      return RequestBody.form(
        parseQs(
          utf8.decode(bytes, allowMalformed: true),
          keepBlankValues: true,
        ),
      );
    case 'multipart/form-data':
      final boundary = MediaType.parse(contentType).parameters['boundary'];
      if (boundary == null) {
        throw ApiException.detail(
          400,
          'Multipart form parse error - Invalid boundary in multipart: None',
        );
      }
      try {
        final form = await parseMultipart(boundary, Stream.value(bytes));
        return RequestBody.form(form.fields, form.files);
      } on MimeMultipartException catch (error) {
        throw ApiException.detail(
          400,
          'Multipart form parse error - ${error.message}',
        );
      }
    default:
      throw ApiException.detail(
        415,
        'Unsupported media type "$contentType" in request.',
      );
  }
}

/// The object a JSON body must be, or linkding's error for anything else.
Map<String, Object?> requireObject(RequestBody body) {
  final json = body.json;
  if (body.isForm) return const {};
  if (json == null) {
    throw ApiException.invalid({
      'non_field_errors': ['No data provided'],
    });
  }
  if (json is! Map<String, Object?>) {
    throw ApiException.invalid({
      'non_field_errors': [
        'Invalid data. Expected a dictionary, but got ${pythonTypeName(json)}.',
      ],
    });
  }
  return json;
}

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

/// Python's `str()` of a JSON value, as it appears in messages.
String pythonStr(Object? value) => switch (value) {
  null => 'None',
  true => 'True',
  false => 'False',
  final String s => s,
  final int i => '$i',
  final double d =>
    d == d.truncateToDouble() && d.abs() < 1e16 ? d.toStringAsFixed(1) : '$d',
  final List<Object?> list => '[${list.map(_repr).join(', ')}]',
  final Map<Object?, Object?> map =>
    '{${map.entries.map((e) => '${_repr(e.key)}: ${_repr(e.value)}').join(', ')}}',
  _ => '$value',
};

String _repr(Object? value) =>
    value is String ? "'${value.replaceAll("'", r"\'")}'" : pythonStr(value);

/// Python's `type(value).__name__` for a JSON value.
String pythonTypeName(Object? value) => switch (value) {
  null => 'NoneType',
  bool() => 'bool',
  String() => 'str',
  int() => 'int',
  double() => 'float',
  List<Object?>() => 'list',
  Map<Object?, Object?>() => 'dict',
  _ => '${value.runtimeType}',
};
