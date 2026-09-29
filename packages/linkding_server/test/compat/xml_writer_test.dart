import 'package:linkding_server/src/compat/xml_writer.dart';
import 'package:test/test.dart';

/// The XML writer behind the feeds, against what Python's
/// `SimplerXMLGenerator` wrote for the same input.
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
}
