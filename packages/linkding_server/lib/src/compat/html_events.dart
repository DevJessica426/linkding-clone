import 'package:html/parser.dart' as html;

/// One event of Python's `html.parser.HTMLParser`: a start tag with its
/// attributes (names lowercased, values unescaped, null for an attribute
/// without a value), an end tag, or text (unescaped).
sealed class HtmlEvent {
  const HtmlEvent();
}

final class StartTag extends HtmlEvent {
  const StartTag(this.name, this.attributes, {this.selfClosing = false});
  final String name;
  final List<(String, String?)> attributes;
  final bool selfClosing;
}

final class EndTag extends HtmlEvent {
  const EndTag(this.name);
  final String name;
}

final class Text extends HtmlEvent {
  const Text(this.data);
  final String data;
}

final _tagName = RegExp(r'[a-zA-Z][^\t\n\r\f />\x00]*');
final _attribute = RegExp(
  r'''[\s/]*([^\s/>][^\s/=>]*)(\s*=+\s*('[^']*'|"[^"]*"|(?!['"])[^>\s]*))?''',
);
final _charref = RegExp(
  r'&(#[0-9]+;?|#[xX][0-9a-fA-F]+;?|[^\t\n\f <&#;]{1,32};?)',
);

/// Python's `html.unescape`, character references decoded as an HTML5
/// parser decodes them in text.
String unescapeHtml(String text) {
  if (!text.contains('&')) return text;
  return text.replaceAllMapped(_charref, (m) {
    final decoded = html.parseFragment(m[0]!).text ?? m[0]!;
    return decoded;
  });
}

/// The events `HTMLParser` reports for [source], with character
/// references in text and attribute values converted
/// (`convert_charrefs=True`). Comments, declarations and processing
/// instructions are skipped; a `<` that starts none of these is a text
/// event by itself.
List<HtmlEvent> htmlEvents(String source) {
  final events = <HtmlEvent>[];
  final text = StringBuffer();
  void flush() {
    if (text.isEmpty) return;
    events.add(Text(unescapeHtml(text.toString())));
    text.clear();
  }

  var i = 0;
  final n = source.length;
  String? rawTextTag;
  while (i < n) {
    if (rawTextTag != null) {
      // script and style: everything up to the end tag is text.
      final end = source.toLowerCase().indexOf('</$rawTextTag', i);
      final stop = end < 0 ? n : end;
      if (stop > i) {
        flush();
        events.add(Text(source.substring(i, stop)));
      }
      i = stop;
      rawTextTag = null;
      continue;
    }
    final lt = source.indexOf('<', i);
    if (lt < 0) {
      text.write(source.substring(i));
      break;
    }
    text.write(source.substring(i, lt));
    i = lt;
    if (source.startsWith('<!--', i)) {
      final end = source.indexOf('-->', i + 4);
      flush();
      i = end < 0 ? n : end + 3;
    } else if (source.startsWith('</', i)) {
      final name = _tagName.matchAsPrefix(source, i + 2);
      final end = source.indexOf('>', i + 2);
      if (end < 0) {
        text.write(source.substring(i));
        break;
      }
      flush();
      if (name != null) events.add(EndTag(name[0]!.toLowerCase()));
      i = end + 1;
    } else if (source.startsWith('<!', i) || source.startsWith('<?', i)) {
      final end = source.indexOf('>', i + 2);
      flush();
      i = end < 0 ? n : end + 1;
    } else if (_tagName.matchAsPrefix(source, i + 1) case final name?) {
      final attributes = <(String, String?)>[];
      var k = name.end;
      while (k < n) {
        final m = _attribute.matchAsPrefix(source, k);
        if (m == null || m.end == k) break;
        var value = m[3];
        if (m[2] == null) {
          value = null;
        } else if (value != null &&
            value.length >= 2 &&
            (value[0] == "'" || value[0] == '"') &&
            value[value.length - 1] == value[0]) {
          value = value.substring(1, value.length - 1);
        }
        attributes.add((
          m[1]!.toLowerCase(),
          value == null || value.isEmpty ? value : unescapeHtml(value),
        ));
        k = m.end;
      }
      final end = source.indexOf('>', k);
      if (end < 0) {
        text.write(source.substring(i));
        break;
      }
      final selfClosing = source.substring(k, end).trim() == '/';
      flush();
      final tag = name[0]!.toLowerCase();
      events.add(StartTag(tag, attributes, selfClosing: selfClosing));
      if (selfClosing) events.add(EndTag(tag));
      if (tag == 'script' || tag == 'style') rawTextTag = tag;
      i = end + 1;
    } else {
      // A `<` that starts nothing is text of its own, between the texts
      // before and after it.
      flush();
      events.add(const Text('<'));
      i++;
    }
  }
  flush();
  return events;
}
