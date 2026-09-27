/// Django's `SimplerXMLGenerator`, which writes linkding's RSS feeds: Python's
/// `xml.sax.saxutils.XMLGenerator` with sorted attributes, short empty
/// elements, and a refusal of control characters in text.
final class SimplerXmlGenerator {
  final _out = StringBuffer();
  var _pendingStart = false;

  static final _controlCharacters = RegExp(r'[\x00-\x08\x0B-\x0C\x0E-\x1F]');

  /// The document so far.
  @override
  String toString() => _out.toString();

  void startDocument() =>
      _out.write('<?xml version="1.0" encoding="utf-8"?>\n');

  void startElement(String name, [Map<String, String> attrs = const {}]) {
    _finishPendingStart();
    _out.write('<$name');
    final names = attrs.keys.toList()..sort();
    for (final key in names) {
      _out.write(' $key=${_quoteAttribute(attrs[key]!)}');
    }
    _pendingStart = true;
  }

  void endElement(String name) {
    if (_pendingStart) {
      _out.write('/>');
      _pendingStart = false;
    } else {
      _out.write('</$name>');
    }
  }

  /// Text; Django fails loudly on characters XML 1.0 cannot hold.
  void characters(String content) {
    if (content.isEmpty) return;
    if (_controlCharacters.hasMatch(content)) {
      throw const UnserializableContentError();
    }
    _finishPendingStart();
    _out.write(_escape(content));
  }

  /// An element with no children: text, or nothing when [contents] is
  /// null (or empty, which Python writes the same way).
  void addQuickElement(
    String name, [
    String? contents,
    Map<String, String> attrs = const {},
  ]) {
    startElement(name, attrs);
    if (contents != null) characters(contents);
    endElement(name);
  }

  void _finishPendingStart() {
    if (!_pendingStart) return;
    _out.write('>');
    _pendingStart = false;
  }

  /// `xml.sax.saxutils.escape`.
  static String _escape(String data) => data
      .replaceAll('&', '&amp;')
      .replaceAll('>', '&gt;')
      .replaceAll('<', '&lt;');

  /// `xml.sax.saxutils.quoteattr`: double quotes, unless the value holds
  /// one and no single quote.
  static String _quoteAttribute(String value) {
    final data = _escape(value)
        .replaceAll('\n', '&#10;')
        .replaceAll('\r', '&#13;')
        .replaceAll('\t', '&#9;');
    if (!data.contains('"')) return '"$data"';
    if (data.contains("'")) return '"${data.replaceAll('"', '&quot;')}"';
    return "'$data'";
  }
}

/// Django's `UnserializableContentError`: text with control characters.
final class UnserializableContentError implements Exception {
  const UnserializableContentError();

  @override
  String toString() => 'Control characters are not supported in XML 1.0';
}
