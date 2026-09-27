import 'dart:convert';
import 'dart:io';

import 'package:linkding_server/src/api/pagination.dart';
import 'package:linkding_server/src/compat/django.dart';
import 'package:linkding_server/src/core/auto_tagging.dart';
import 'package:linkding_server/src/core/urls.dart';
import 'package:linkding_shared/linkding_shared.dart';
import 'package:test/test.dart';

/// The server's ports of linkding, Django and DRF helpers against output
/// recorded from the originals by `tool/logic_fixture.py`.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/logic.json').readAsStringSync(),
  ) as Map<String, Object?>;
  List<List<Object?>> rows(String key) =>
      (fixture[key]! as List<Object?>).cast<List<Object?>>();

  group('Django URLValidator', () {
    for (final [url as String, valid as bool] in rows('url_valid')) {
      test(jsonEncode(url), () => expect(isValidUrl(url), valid));
    }
  });

  group('normalize_url', () {
    for (final [url as String, normalized as String] in rows('normalize_url')) {
      test(jsonEncode(url), () => expect(normalizeUrl(url), normalized));
    }
  });

  group('parse_tag_string', () {
    for (final [input as String, commas, spaces] in rows('tag_strings')) {
      test(jsonEncode(input), () {
        expect(parseTagString(input), commas);
        expect(parseTagString(input, delimiter: ' '), spaces);
      });
    }
  });

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
    for (final [rule as String, url as String, tags] in rows(
      'auto_tagging_single',
    )) {
      test('${jsonEncode(rule)}, ${jsonEncode(url)}', () {
        expect(tagsOrError(rule, url), expected(tags));
      });
    }
  });

  group('DRF pagination links', () {
    for (final [url as String, withLimit, withOffset, withoutOffset] in rows(
      'page_links',
    )) {
      test(url, () {
        expect(replaceQueryParam(url, 'limit', '5'), withLimit);
        expect(
          replaceQueryParam(
            replaceQueryParam(url, 'limit', '5'),
            'offset',
            '15',
          ),
          withOffset,
        );
        expect(removeQueryParam(url, 'offset'), withoutOffset);
      });
    }
  });

  String? iso(DateTime? value) => value == null ? null : _pythonIso(value);

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

    for (final [input as String, datetime, date] in rows('parse_datetime')) {
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
    for (final [input as String, recorded] in rows('drf_datetime')) {
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

  test('web archive fallback URL', () {
    for (final [url as String, at as String, expectedUrl] in rows(
      'web_archive',
    )) {
      expect(webArchiveFallbackUrl(url, DateTime.parse(at)), expectedUrl);
    }
  });
}

/// Python's `datetime.isoformat()` for an aware UTC value (dates from
/// `parse_date` are naive dates, written without a time).
String _pythonIso(DateTime value) {
  final utc = value.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final micros = utc.millisecond * 1000 + utc.microsecond;
  final fraction = micros == 0 ? '' : '.${micros.toString().padLeft(6, '0')}';
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}'
      'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}$fraction+00:00';
}
