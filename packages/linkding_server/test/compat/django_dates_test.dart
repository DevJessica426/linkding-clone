import 'dart:convert';

import 'package:linkding_server/src/compat/django_dates.dart';
import 'package:test/test.dart';

import '../support/fixtures.dart';

/// Django's date parsing and DRF's `DateTimeField`, against what they read
/// from each input.
void main() {
  final fixture = loadFixture('logic');
  String? iso(DateTime? value) => value == null ? null : pythonIso(value);

  group('Django parse_datetime and parse_date', () {
    // Python records naive values without a zone, keeps offsets, and writes
    // dates without a time; the server only ever uses the instant, in UTC.
    Object? instant(Object? recorded) {
      if (recorded is! String || recorded == 'error') return recorded;
      final dated = recorded.contains('T') ? recorded : '${recorded}T00:00:00';
      final zoned = RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(dated)
          ? dated
          : '${dated}Z';
      return iso(DateTime.parse(zoned));
    }

    for (final [input as String, datetime, date] in fixtureRows(
      fixture,
      'parse_datetime',
    )) {
      test(jsonEncode(input), () {
        Object? run(DateTime? Function(String) parse) {
          try {
            return iso(parse(input));
          } on FormatException {
            return 'error';
          }
        }

        expect(run(parseDjangoDateTime), instant(datetime));
        expect(run(parseDjangoDate), instant(date));
      });
    }
  });

  group('DRF DateTimeField', () {
    for (final [input as String, recorded] in fixtureRows(
      fixture,
      'drf_datetime',
    )) {
      test(jsonEncode(input), () {
        final parsed = parseDrfDateTime(input);
        if (recorded is Map) {
          expect(parsed.error, recorded['error']);
        } else {
          expect(iso(parsed.value), recorded);
        }
      });
    }
  });
}
