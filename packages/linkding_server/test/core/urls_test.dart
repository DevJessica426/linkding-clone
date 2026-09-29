import 'dart:convert';

import 'package:linkding_server/src/core/urls.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// linkding's URL helpers, against what linkding computed.
void main() {
  final fixture = loadFixture('logic');

  group('normalize_url', () {
    for (final [url as String, normalized as String] in fixtureRows(
      fixture,
      'normalize_url',
    )) {
      test(jsonEncode(url), () => expect(normalizeUrl(url), normalized));
    }
  });

  test('web archive fallback URL', () {
    for (final [url as String, at as String, expected] in fixtureRows(
      fixture,
      'web_archive',
    )) {
      expect(webArchiveFallbackUrl(url, DateTime.parse(at)), expected);
    }
  });
}
