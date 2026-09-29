import 'dart:convert';

import 'package:linkding_server/src/core/auto_tagging.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// linkding's `auto_tagging.get_tags`, against what it returned for each
/// rule set and URL.
void main() {
  final fixture = loadFixture('logic');

  Object? tagsOrError(String rules, String url) {
    try {
      return autoTags(rules, url).toList()..sort();
    } on AutoTaggingError {
      return 'error';
    }
  }

  Object? expected(Object? recorded) => recorded is Map ? 'error' : recorded;

  group('auto_tagging.get_tags', () {
    final section = fixture['auto_tagging']! as Map<String, Object?>;
    final rules = section['rules']! as String;
    for (final [url as String, tags]
        in (section['cases']! as List<Object?>).cast<List<Object?>>()) {
      test('all rules, ${jsonEncode(url)}', () {
        expect(tagsOrError(rules, url), expected(tags));
      });
    }
    for (final [rule as String, url as String, tags] in fixtureRows(
      fixture,
      'auto_tagging_single',
    )) {
      test('${jsonEncode(rule)}, ${jsonEncode(url)}', () {
        expect(tagsOrError(rule, url), expected(tags));
      });
    }
  });
}
