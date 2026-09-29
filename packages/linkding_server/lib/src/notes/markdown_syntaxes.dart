import 'package:markdown/markdown.dart' as md;

/// Python-Markdown's lists start only at the beginning of a block: a line
/// starting with `-` right after a paragraph line stays in the paragraph,
/// except inside a list item, where it starts a nested list.
final class NotesUnorderedListSyntax extends md.UnorderedListSyntax {
  const NotesUnorderedListSyntax();

  @override
  bool canParse(md.BlockParser parser) =>
      !_parenItem.hasMatch(parser.current.content) && super.canParse(parser);

  @override
  bool canEndBlock(md.BlockParser parser) =>
      parser.parentSyntax is md.ListSyntax && super.canEndBlock(parser);
}

final class NotesOrderedListSyntax extends md.OrderedListSyntax {
  const NotesOrderedListSyntax();

  @override
  bool canParse(md.BlockParser parser) =>
      !_parenItem.hasMatch(parser.current.content) && super.canParse(parser);

  @override
  bool canEndBlock(md.BlockParser parser) =>
      parser.parentSyntax is md.ListSyntax && super.canEndBlock(parser);
}

/// `1)` does not start a list item in Python-Markdown, only `1.` does.
final _parenItem = RegExp(r'^ {0,3}\d{1,9}\)');

/// Python-Markdown's `#` headers: the marks must start the line, need no
/// space after them, and may interrupt a paragraph, so `#tag` on a line of
/// its own is a heading.
final class NotesHashHeaderSyntax extends md.HeaderSyntax {
  const NotesHashHeaderSyntax();

  static final _hashHeader = RegExp(r'^(#{1,6})(.*?)#*$');

  @override
  RegExp get pattern => _hashHeader;

  @override
  md.Node parse(md.BlockParser parser) {
    final match = _hashHeader.firstMatch(parser.current.content)!;
    parser.advance();
    return md.Element('h${match[1]!.length}', [
      md.UnparsedContent(match[2]!.trim()),
    ]);
  }
}

/// Python-Markdown's tags that make a line raw HTML; any other tag, such as
/// `<b>` or `<img>`, is inline and ends up in a paragraph.
const _blockLevelTags = {
  'address', 'article', 'aside', 'blockquote', 'body', 'canvas', 'center', //
  'colgroup', 'dd', 'details', 'div', 'dl', 'dt', 'fieldset', 'figcaption',
  'figure', 'footer', 'form', 'group', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'header', 'hgroup', 'hr', 'html', 'iframe', 'legend', 'li', 'main', 'map',
  'math', 'menu', 'nav', 'noscript', 'object', 'ol', 'option', 'output', 'p',
  'pre', 'progress', 'script', 'section', 'style', 'summary', 'table',
  'tbody', 'td', 'textarea', 'tfoot', 'th', 'thead', 'tr', 'ul', 'video',
};

final class NotesHtmlBlockSyntax extends md.HtmlBlockSyntax {
  const NotesHtmlBlockSyntax();

  static final _tag = RegExp(r'^</?([a-zA-Z][a-zA-Z0-9-]*)');

  @override
  bool canParse(md.BlockParser parser) {
    final line = parser.current.content;
    if (line.startsWith('<!--')) return super.canParse(parser);
    final tag = _tag.firstMatch(line)?[1]?.toLowerCase();
    return tag != null &&
        _blockLevelTags.contains(tag) &&
        super.canParse(parser);
  }
}

/// `nl2br`: every newline inside a paragraph is a line break. Two spaces
/// before it are Markdown's own line break and are dropped with it.
final class NotesNewlineSyntax extends md.InlineSyntax {
  NotesNewlineSyntax() : super(r'( *)\n');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final spaces = match[1]!.length;
    final kept = spaces >= 2 ? spaces - 2 : spaces;
    if (kept > 0) parser.addNode(md.Text(' ' * kept));
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}
