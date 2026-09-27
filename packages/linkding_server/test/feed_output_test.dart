import 'package:linkding_server/src/compat/django.dart';
import 'package:linkding_server/src/compat/xml_writer.dart';
import 'package:linkding_server/src/web/site_views.dart';
import 'package:test/test.dart';

/// The writers behind the feeds and the manifest, against what Python and
/// Django 6.0 wrote for the same input.
void main() {
  test('SimplerXMLGenerator: escaping, sorted attributes, empty elements', () {
    final xml = SimplerXmlGenerator()
      ..startDocument()
      ..startElement('rss', {'version': '2.0', 'b': 'x'})
      ..addQuickElement('title', 'a < b & c > d "q" \'r\'')
      ..addQuickElement('empty', '')
      ..addQuickElement('none', null, {
        'z': '1',
        'a': 'say "hi"',
        'm': 'it\'s "both"\n\t',
      })
      ..addQuickElement('single', null, {'q': "it's"})
      ..endElement('rss');
    expect(
      xml.toString(),
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<rss b="x" version="2.0"><title>a &lt; b &amp; c &gt; d "q" \'r\''
      '</title><empty/><none a=\'say "hi"\' '
      'm="it\'s &quot;both&quot;&#10;&#9;" z="1"/><single q="it\'s"/></rss>',
    );
  });

  test('SimplerXMLGenerator refuses control characters in text', () {
    final xml = SimplerXmlGenerator()..startElement('a');
    expect(
      () => xml.characters('bell\x07'),
      throwsA(isA<UnserializableContentError>()),
    );
    // Line breaks and tabs are fine.
    xml.characters('a\nb\tc\r');
  });

  test('iri_to_uri', () {
    expect(
      iriToUri('http://ex.com/päth?q=a b&x=%20#frag|{}'),
      'http://ex.com/p%C3%A4th?q=a%20b&x=%20#frag%7C%7B%7D',
    );
  });

  test('rfc2822_date', () {
    expect(
      rfc2822Date(DateTime.utc(2026, 1, 5, 3, 4, 5, 0, 999)),
      'Mon, 05 Jan 2026 03:04:05 +0000',
    );
  });

  test('int() as Python reads a query value', () {
    expect(pythonInt(' 1_0 '), 10);
    expect(pythonInt('+3'), 3);
    expect(pythonInt('-0'), 0);
    for (final bad in ['', 'x', '1.5', '1__0', '_1', '1_']) {
      expect(pythonInt(bad), isNull, reason: bad);
    }
  });

  test("json.dumps's default separators", () {
    expect(
      pythonJson({
        'a': [1, 'b'],
        'c': {'d': true, 'e': null},
      }),
      '{"a": [1, "b"], "c": {"d": true, "e": null}}',
    );
  });
}
