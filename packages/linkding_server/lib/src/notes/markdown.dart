import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;

import 'markdown_clean.dart';
import 'markdown_syntaxes.dart';

/// Renders a bookmark's notes as linkding's `{% markdown %}` tag does:
/// Python-Markdown with fenced code and `nl2br`, cleaned by bleach to the
/// allowlist, then linkified by bleach with `rel="nofollow"` and schemeless
/// links made https.
///
/// Known differences: a nested list needs no four-space indent, and spaces
/// at the end of a paragraph are dropped.
String renderNotes(String source) {
  final document = md.Document(
    withDefaultBlockSyntaxes: false,
    blockSyntaxes: const [
      md.EmptyBlockSyntax(),
      NotesHtmlBlockSyntax(),
      md.SetextHeaderSyntax(),
      NotesHashHeaderSyntax(),
      md.CodeBlockSyntax(),
      md.FencedCodeBlockSyntax(),
      md.BlockquoteSyntax(),
      md.HorizontalRuleSyntax(),
      NotesUnorderedListSyntax(),
      NotesOrderedListSyntax(),
      md.LinkReferenceDefinitionSyntax(),
      md.ParagraphSyntax(),
    ],
    inlineSyntaxes: [NotesNewlineSyntax(), md.InlineHtmlSyntax()],
    encodeHtml: true,
  );
  // Character references go through as placeholders, so they come out as
  // written, the way bleach keeps them, rather than as characters.
  final references = <String>[];
  final protected = _expandTabs(source).replaceAllMapped(_reference, (m) {
    references.add(m[0]!);
    return '\uE000${references.length - 1}\uE001';
  });
  final rendered = md.renderToHtml(document.parseLines(protected.split('\n')));
  final out = StringBuffer();
  for (final node in html.parseFragment(rendered).nodes) {
    cleanNode(node, out, references, inLink: false, inCode: false);
  }
  return out.toString().replaceAllMapped(referencePlaceholder, (m) {
    final reference = references[int.parse(m[1]!)];
    return _isKnownReference(reference)
        ? reference
        : '&amp;${reference.substring(1)}';
  });
}

final _reference = RegExp(
  r'&(?:#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{0,31});',
);

/// Whether the HTML parser knows [reference] (`&copy;`, `&#169;`).
bool _isKnownReference(String reference) =>
    html.parseFragment(reference).text != reference;

/// Python's `str.expandtabs(4)`, which Python-Markdown applies first.
String _expandTabs(String text) {
  if (!text.contains('\t')) return text;
  final out = StringBuffer();
  var column = 0;
  for (final rune in text.runes) {
    if (rune == 0x09) {
      final spaces = 4 - column % 4;
      out.write(' ' * spaces);
      column += spaces;
    } else {
      out.writeCharCode(rune);
      column = rune == 0x0a || rune == 0x0d ? 0 : column + 1;
    }
  }
  return out.toString();
}
