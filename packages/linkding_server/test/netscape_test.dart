import 'dart:convert';
import 'dart:io';

import 'package:linkding_server/src/services/netscape.dart';
import 'package:test/test.dart';

/// The Netscape bookmark file reader against linkding's own parser and
/// timestamp reading, recorded by `tool/netscape_fixture.py`.
void main() {
  final fixture = jsonDecode(
    File('test/fixtures/netscape.json').readAsStringSync(),
  ) as Map<String, Object?>;

  group('parser.parse', () {
    for (final [source as String, expected as List<Object?>]
        in (fixture['documents']! as List<Object?>).cast<List<Object?>>()) {
      test(jsonEncode(source), () {
        final parsed = [
          for (final b in parseNetscape(source))
            {
              'href': b.href,
              'href_normalized': b.hrefNormalized,
              'title': b.title,
              'description': b.description,
              'notes': b.notes,
              'date_added': b.dateAdded,
              'date_modified': b.dateModified,
              'tag_names': b.tagNames,
              'to_read': b.toRead,
              'private': b.private,
              'archived': b.archived,
            },
        ];
        expect(parsed, expected);
      });
    }
  });

  group('parse_timestamp', () {
    for (final [value as String, expected as String?]
        in (fixture['timestamps']! as List<Object?>).cast<List<Object?>>()) {
      test(jsonEncode(value), () {
        expect(
          parseTimestamp(value),
          expected == null ? isNull : DateTime.parse(expected),
        );
      });
    }
  });
}
