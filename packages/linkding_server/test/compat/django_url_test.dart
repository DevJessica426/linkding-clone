import 'dart:convert';

import 'package:linkding_server/src/compat/django_url.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// Django's `URLValidator`, against what Django answered for each URL.
void main() {
  final fixture = loadFixture('logic');
  group('Django URLValidator', () {
    for (final [url as String, valid as bool] in fixtureRows(
      fixture,
      'url_valid',
    )) {
      test(jsonEncode(url), () => expect(isValidUrl(url), valid));
    }
  });
}
