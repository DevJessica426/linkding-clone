import 'dart:convert';
import 'dart:typed_data';

import 'package:dust_server/server.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import 'pyurl.dart';

/// A file sent with a form.
final class FormFile {
  const FormFile(this.name, this.contentType, this.bytes);

  final String name;
  final String contentType;
  final Uint8List bytes;
}

/// A submitted form: `request.POST` and `request.FILES`. Keys keep every
/// value; [operator []] gives the last, as `QueryDict.get` does.
final class FormData {
  const FormData(this.fields, [this.files = const {}]);

  final Map<String, List<String>> fields;
  final Map<String, FormFile> files;

  String? operator [](String key) => fields[key]?.last;

  bool has(String key) => fields.containsKey(key);

  List<String> list(String key) => fields[key] ?? const [];
}

/// Reads a urlencoded or multipart form body.
Future<FormData> readFormData(Request request) async {
  final type = request.headers['content-type'];
  final media = type == null ? null : MediaType.parse(type);
  if (media?.mimeType != 'multipart/form-data') {
    return FormData(
      parseQs(await request.readAsString(), keepBlankValues: true),
    );
  }
  final boundary = media!.parameters['boundary'];
  if (boundary == null) return const FormData({});
  return parseMultipart(boundary, request.read());
}

/// A `multipart/form-data` body: text parts as fields, parts with a file
/// name as files, named as Django names them (the name without its path).
/// Throws a [MimeMultipartException] for a body that is not multipart.
Future<FormData> parseMultipart(String boundary, Stream<List<int>> body) async {
  final fields = <String, List<String>>{};
  final files = <String, FormFile>{};
  // A request body is a `Stream<Uint8List>`, which the transformer's
  // `List<int>` input type does not accept as it is.
  final parts = body.cast<List<int>>().transform(
    MimeMultipartTransformer(boundary),
  );
  await for (final part in parts) {
    final disposition = part.headers['content-disposition'];
    if (disposition == null) continue;
    final params = _dispositionParams(disposition);
    final name = params['name'];
    if (name == null) continue;
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in part) {
      bytes.add(chunk);
    }
    final filename = params['filename']?.split(RegExp(r'[\\/]')).last.trim();
    if (filename == null) {
      (fields[name] ??= []).add(
        utf8.decode(bytes.takeBytes(), allowMalformed: true),
      );
    } else if (filename.isNotEmpty) {
      // Django keeps the media type, lowercased, without its parameters.
      final type = part.headers['content-type']?.split(';').first.trim();
      files[name] = FormFile(
        filename,
        type == null || type.isEmpty
            ? 'application/octet-stream'
            : type.toLowerCase(),
        bytes.takeBytes(),
      );
    }
  }
  return FormData(fields, files);
}

Map<String, String> _dispositionParams(String header) {
  final params = <String, String>{};
  for (final match in RegExp(
    r';\s*([^=;\s]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^;]*))',
  ).allMatches(header)) {
    params[match[1]!.toLowerCase()] =
        match[2]?.replaceAllMapped(RegExp(r'\\(.)'), (m) => m[1]!) ??
        match[3]!.trim();
  }
  return params;
}

/// The submitted form as a handler reads it: `request.POST` for a POST,
/// empty for anything else, as Django parses only POST bodies.
final class PostedForm implements FromRequest<FormData> {
  const PostedForm();

  @override
  Future<Result<FormData, Rejection>> extract(Request request) async =>
      Ok(request.method == 'POST' ? await readFormData(request) : _empty);
}

const _empty = FormData({});
