import 'dart:convert';
import 'dart:typed_data';

import 'package:dust_server/server.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

import '../compat/pyurl.dart';
import 'html.dart';

/// A file sent with a form.
final class UploadedFile {
  const UploadedFile(this.name, this.contentType, this.bytes);

  final String name;
  final String contentType;
  final Uint8List bytes;
}

/// A submitted form: `request.POST` and `request.FILES`. Keys keep every
/// value; [operator []] gives the last, as `QueryDict.get` does.
final class FormData {
  const FormData(this.fields, [this.files = const {}]);

  final Map<String, List<String>> fields;
  final Map<String, UploadedFile> files;

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

  final fields = <String, List<String>>{};
  final files = <String, UploadedFile>{};
  final parts = request.read().transform(MimeMultipartTransformer(boundary));
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
    final filename = params['filename'];
    if (filename == null) {
      (fields[name] ??= []).add(utf8.decode(bytes.takeBytes()));
    } else if (filename.isNotEmpty) {
      files[name] = UploadedFile(
        filename,
        part.headers['content-type'] ?? 'application/octet-stream',
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
