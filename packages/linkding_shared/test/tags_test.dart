import 'dart:convert';
import 'dart:io';

import 'package:linkding_shared/linkding_shared.dart';
import 'package:test/test.dart';

/// `parse_tag_string`, against what linkding returned for each input,
/// recorded by `tool/logic_fixture.py`.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/tag_strings.json').readAsStringSync(),
  ) as Map<String, Object?>;
  group('parse_tag_string', () {
    for (final [input as String, commas, spaces]
        in (fixture['tag_strings']! as List<Object?>).cast<List<Object?>>()) {
      test(jsonEncode(input), () {
        expect(parseTagString(input), commas);
        expect(parseTagString(input, delimiter: ' '), spaces);
      });
    }
  });
}
