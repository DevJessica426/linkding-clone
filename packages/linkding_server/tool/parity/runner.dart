import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'normalize.dart';
import 'step.dart';
import 'steps.dart';

Future<List<Object?>> runSteps(
  String base,
  String token,
  String database,
) async {
  final client = http.Client();
  final results = <Object?>[];
  for (final step in steps) {
    if (step.sql case final sql?) {
      final result = await Process.run('psql', [
        database,
        '-v',
        'ON_ERROR_STOP=1',
        '-qc',
        sql,
      ]);
      results.add(result.exitCode == 0 ? 'ok' : 'failed: ${result.stderr}');
      continue;
    }
    final request = http.Request(step.method, Uri.parse('$base${step.path}'))
      ..followRedirects = false;
    switch (step.auth) {
      case Auth.token:
        request.headers['authorization'] = 'Token $token';
      case Auth.bearer:
        request.headers['authorization'] = 'Bearer $token';
      case Auth.badToken:
        request.headers['authorization'] = 'Token nope';
      case Auth.emptyToken:
        request.headers['authorization'] = 'Token';
      case Auth.none:
        break;
    }
    if (step.files case final files?) {
      final multipart =
          http.MultipartRequest(step.method, Uri.parse('$base${step.path}'))
            ..followRedirects = false
            ..headers.addAll(request.headers)
            ..fields.addAll({
              for (final e in (step.form ?? const {}).entries)
                e.key: '${e.value}',
            });
      for (final (field, name, type, content) in files) {
        multipart.files.add(
          http.MultipartFile.fromString(
            field,
            content,
            filename: name,
            contentType: MediaType.parse(type),
          ),
        );
      }
      final response = await http.Response.fromStream(
        await client.send(multipart),
      );
      results.add(normalize(base, response));
      continue;
    }
    if (step.json != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(step.json);
    } else if (step.form != null) {
      request.bodyFields = {
        for (final e in step.form!.entries) e.key: '${e.value}',
      };
    } else if (step.raw != null) {
      request.headers['content-type'] = step.contentType!;
      request.body = step.raw!;
    }
    final response = await http.Response.fromStream(await client.send(request));
    results.add(normalize(base, response));
  }
  client.close();
  return results;
}
