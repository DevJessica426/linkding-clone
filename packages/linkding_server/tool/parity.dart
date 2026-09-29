/// Sends the same requests to a real linkding and to this clone and
/// compares what comes back.
///
///     dart run tool/parity.dart http://localhost:9090=<token> \
///         http://localhost:9091=<token>
///
/// Both servers must start from an empty database with one user, so ids line
/// up; `tool/parity.sh` at the repository root prepares that. Each step's
/// status, key headers and JSON body are compared after normalizing only
/// what must differ: timestamps taken "now", the host in absolute URLs, and
/// Python's wording inside JSON parse errors. HTML bodies are compared by
/// content type only.
///
/// One difference is known and not reported: Dart's `HttpServer` gives a
/// `204 No Content` a `content-type: text/plain` default, which `dust_server`
/// offers no way to switch off. linkding sends none.
library;

import 'dart:convert';
import 'dart:io';

import 'parity/normalize.dart';
import 'parity/runner.dart';
import 'parity/steps.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    stderr.writeln(
      'usage: parity.dart <base>=<token>=<database url> '
      '<base>=<token>=<database url>',
    );
    exit(2);
  }
  final [reference, clone] = [for (final arg in args) arg.split('=')];
  final left = await runSteps(reference[0], reference[1], reference[2]);
  final right = await runSteps(clone[0], clone[1], clone[2]);

  var failures = 0;
  for (var i = 0; i < steps.length; i++) {
    final a = const JsonEncoder.withIndent('  ').convert(left[i]);
    final b = const JsonEncoder.withIndent('  ')
        .convert(sameSizes(left[i], right[i]));
    if (a == b) continue;
    failures++;
    stdout
      ..writeln('✗ ${steps[i].method} ${steps[i].path} — ${steps[i].name}')
      ..writeln('  linkding: ${jsonEncode(left[i])}')
      ..writeln('  clone:    ${jsonEncode(right[i])}');
  }
  stdout.writeln(
    '\n${steps.length - failures} of ${steps.length} requests answered the same'
    '${failures == 0 ? '' : '; $failures differ'}.',
  );
  exitCode = failures == 0 ? 0 : 1;
}
