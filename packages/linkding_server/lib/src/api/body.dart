import 'dart:convert';

import 'package:dust_server/server.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../compat/form_data.dart';
import '../compat/python_values.dart';
import '../compat/pyurl.dart';
import 'errors.dart';

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
