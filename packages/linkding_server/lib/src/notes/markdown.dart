import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;

/// Tags and attributes linkding lets through (`bleach_allowlist`'s
/// markdown lists); any other tag is escaped into text, and any other
/// attribute dropped.
const _allowedTags = {
  'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'b', 'i', 'strong', 'em', 'tt', 'p', //
  'br', 'span', 'div', 'blockquote', 'code', 'pre', 'hr', 'ul', 'ol', 'li',
  'dd', 'dt', 'img', 'a', 'sub', 'sup',
};
const _allowedAttributes = {
  'img': {'src', 'alt', 'title', 'id'},
  'a': {'href', 'alt', 'title', 'id'},
};
const _allowedSchemes = {'http', 'https', 'mailto'};
const _voidTags = {'br', 'hr', 'img'};

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
      _HtmlBlockSyntax(),
      md.SetextHeaderSyntax(),
      _HashHeaderSyntax(),
      md.CodeBlockSyntax(),
      md.FencedCodeBlockSyntax(),
      md.BlockquoteSyntax(),
      md.HorizontalRuleSyntax(),
      _UnorderedListSyntax(),
      _OrderedListSyntax(),
      md.LinkReferenceDefinitionSyntax(),
      md.ParagraphSyntax(),
    ],
    inlineSyntaxes: [_NewlineSyntax(), md.InlineHtmlSyntax()],
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
    _clean(node, out, references, inLink: false, inCode: false);
  }
  return out.toString().replaceAllMapped(_placeholder, (m) {
    final reference = references[int.parse(m[1]!)];
    return _isKnownReference(reference)
        ? reference
        : '&amp;${reference.substring(1)}';
  });
}

final _reference = RegExp(
  r'&(?:#[0-9]{1,7}|#[xX][0-9a-fA-F]{1,6}|[A-Za-z][A-Za-z0-9]{0,31});',
);
final _placeholder = RegExp('\uE000([0-9]+)\uE001');

/// Whether the HTML parser knows [reference] (`&copy;`, `&#169;`).
bool _isKnownReference(String reference) =>
    html.parseFragment(reference).text != reference;

/// Python-Markdown's lists start only at the beginning of a block: a line
/// starting with `-` right after a paragraph line stays in the paragraph,
/// except inside a list item, where it starts a nested list.
final class _UnorderedListSyntax extends md.UnorderedListSyntax {
  const _UnorderedListSyntax();

  @override
  bool canParse(md.BlockParser parser) =>
      !_parenItem.hasMatch(parser.current.content) && super.canParse(parser);

  @override
  bool canEndBlock(md.BlockParser parser) =>
      parser.parentSyntax is md.ListSyntax && super.canEndBlock(parser);
}

final class _OrderedListSyntax extends md.OrderedListSyntax {
  const _OrderedListSyntax();

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
final class _HashHeaderSyntax extends md.HeaderSyntax {
  const _HashHeaderSyntax();

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

final class _HtmlBlockSyntax extends md.HtmlBlockSyntax {
  const _HtmlBlockSyntax();

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
final class _NewlineSyntax extends md.InlineSyntax {
  _NewlineSyntax() : super(r'( *)\n');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final spaces = match[1]!.length;
    final kept = spaces >= 2 ? spaces - 2 : spaces;
    if (kept > 0) parser.addNode(md.Text(' ' * kept));
    parser.addNode(md.Element.empty('br'));
    return true;
  }
}

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

/// Writes [node] as bleach's `clean` and then `linkify` would.
void _clean(
  dom.Node node,
  StringBuffer out,
  List<String> references, {
  required bool inLink,
  required bool inCode,
}) {
  if (node is dom.Text) {
    var text = node.text;
    // Python-Markdown escapes `&` in code, references included.
    if (inCode) {
      text = text.replaceAllMapped(
        _placeholder,
        (m) => references[int.parse(m[1]!)],
      );
    }
    out.write(inLink ? _escapeText(text) : _linkify(text));
    return;
  }
  if (node is! dom.Element) return;
  final tag = node.localName!;
  if (!_allowedTags.contains(tag)) {
    // bleach escapes a disallowed tag, attributes and all, keeping its
    // content.
    final attributes = [
      for (final MapEntry(:key, :value) in node.attributes.entries)
        ' $key="$value"',
    ].join();
    _clean(
      dom.Text('<$tag$attributes>'),
      out,
      references,
      inLink: inLink,
      inCode: inCode,
    );
    for (final child in node.nodes) {
      _clean(child, out, references, inLink: inLink, inCode: inCode);
    }
    if (!_voidTags.contains(tag)) {
      _clean(
        dom.Text('</$tag>'),
        out,
        references,
        inLink: inLink,
        inCode: inCode,
      );
    }
    return;
  }

  final allowed = _allowedAttributes[tag] ?? const {'id'};
  final attributes = <String, String>{};
  for (final key in node.attributes.keys.map((k) => '$k').toList()..sort()) {
    final value = node.attributes[key]!;
    if (!allowed.contains(key)) continue;
    if ((key == 'href' || key == 'src') && !_safeUrl(value)) continue;
    attributes[key] = value;
  }
  if (tag == 'a') {
    _linkCallbacks(attributes, node.text);
  }
  out.write('<$tag');
  attributes.forEach(
    (key, value) => out.write(' $key="${_escapeAttribute(value)}"'),
  );
  out.write('>');
  if (_voidTags.contains(tag)) return;
  final children = node.nodes.toList();
  for (final (i, child) in children.indexed) {
    // A tight list item's text runs straight into a nested list.
    if (tag == 'li' &&
        child is dom.Text &&
        i + 1 < children.length &&
        const {
          'ul',
          'ol',
          'p',
          'pre',
          'blockquote',
        }.contains((children[i + 1] as dom.Element?)?.localName)) {
      _clean(
        dom.Text(child.text.trimRight()),
        out,
        references,
        inLink: inLink,
        inCode: inCode,
      );
      continue;
    }
    _clean(
      child,
      out,
      references,
      inLink: inLink || tag == 'a',
      inCode: inCode || tag == 'code' || tag == 'pre',
    );
  }
  out.write('</$tag>');
}

/// bleach keeps a URL whose scheme is allowed, or that has none.
bool _safeUrl(String value) {
  final trimmed = value.replaceAll(RegExp(r'[\x00-\x20]'), '');
  final match = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*):').firstMatch(trimmed);
  if (match == null) return true;
  return _allowedSchemes.contains(match[1]!.toLowerCase());
}

/// html5lib's serializer: text escapes `&`, `<` and `>`.
String _escapeText(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String _escapeAttribute(String value) =>
    value.replaceAll('&', '&amp;').replaceAll('"', '&quot;');

/// linkding's link callbacks: bleach's `nofollow`, then
/// `schemeless_urls_to_https`, which also applies to existing links unless
/// their text spells out `http://`.
void _linkCallbacks(Map<String, String> attributes, String text) {
  final href = attributes['href'];
  if (href == null) return;
  if (!href.startsWith('mailto:')) {
    final rel = (attributes['rel'] ?? '')
        .split(' ')
        .where((v) => v.isNotEmpty)
        .toList();
    if (!rel.any((v) => v.toLowerCase() == 'nofollow')) rel.add('nofollow');
    attributes['rel'] = rel.join(' ');
  }
  if (!text.startsWith('http://')) {
    attributes['href'] = href.replaceFirst(RegExp('^http://'), 'https://');
  }
}

const _protocols = [
  'afs', 'aim', 'callto', 'data', 'ed2k', 'feed', 'ftp', 'gopher', 'http', //
  'https', 'irc', 'mailto', 'news', 'nntp', 'rsync', 'rtsp', 'sftp', 'ssh',
  'tag', 'telnet', 'urn', 'webcal', 'xmpp',
];

/// bleach's top-level domains, sorted as its pattern lists them.
final _tlds =
    ('ac ad ae aero af ag ai al am an ao aq ar arpa as asia at au aw '
            'ax az ba bb bd be bf bg bh bi biz bj bm bn bo br bs bt bv bw by bz '
            'ca cat cc cd cf cg ch ci ck cl cm cn co com coop cr cu cv cx cy cz '
            'de dj dk dm do dz ec edu ee eg er es et eu fi fj fk fm fo fr ga gb '
            'gd ge gf gg gh gi gl gm gn gov gp gq gr gs gt gu gw gy hk hm hn hr '
            'ht hu id ie il im in info int io iq ir is it je jm jo jobs jp ke kg '
            'kh ki km kn kp kr kw ky kz la lb lc li lk lr ls lt lu lv ly ma mc md '
            'me mg mh mil mk ml mm mn mo mobi mp mq mr ms mt mu museum mv mw mx '
            'my mz na name nc ne net nf ng ni nl no np nr nu nz om org pa pe pf '
            'pg ph pk pl pm pn post pr pro ps pt pw py qa re ro rs ru rw sa sb sc '
            'sd se sg sh si sj sk sl sm sn so sr ss st su sv sx sy sz tc td tel '
            'tf tg th tj tk tl tm tn to tp tr travel tt tv tw tz ua ug uk us uy '
            'uz va vc ve vg vi vn vu wf ws xn xxx ye yt yu za zm zw')
        .split(' ')
      ..sort();

/// Python's Unicode `\w` and `\b`.
const _w = r'[\p{L}\p{N}_]';
const _boundary = '(?:(?<=$_w)(?!$_w)|(?<!$_w)(?=$_w))';

/// bleach's `URL_RE`.
final _urlPattern = RegExp(
  r'\(*'
  '$_boundary(?<![@.])(?:(?:${_protocols.join('|')}):/{0,3}'
  '(?:(?:$_w+:)?$_w+@)?)?'
  r'(?:[\p{L}\p{N}_-]+\.)+'
  '(?:${_tlds.join('|')})(?::[0-9]+)?(?!\\.$_w)$_boundary'
  r'(?:[/?][^\s{}|\\^`<>"]*)?',
  caseSensitive: false,
  unicode: true,
);

final _protocolPattern = RegExp(r'^[\p{L}\p{N}_-]+:/{0,3}', unicode: true);

/// bleach's `linkify` over one run of text.
String _linkify(String text) {
  final out = StringBuffer();
  var end = 0;
  for (final match in _urlPattern.allMatches(text)) {
    out.write(_escapeText(text.substring(end, match.start)));
    final (url, prefix, suffix) = _stripNonUrlBits(match[0]!);
    final attributes = <String, String>{
      'href': _protocolPattern.hasMatch(url) ? url : 'http://$url',
    };
    _linkCallbacks(attributes, url);
    out
      ..write(_escapeText(prefix))
      ..write('<a')
      ..writeAll([
        for (final MapEntry(:key, :value) in attributes.entries)
          ' $key="${_escapeAttribute(value)}"',
      ])
      ..write('>${_escapeText(url)}</a>')
      ..write(_escapeText(suffix));
    end = match.end;
  }
  out.write(_escapeText(text.substring(end)));
  return out.toString();
}

/// bleach's `strip_non_url_bits`: balanced parentheses around a URL, and a
/// closing parenthesis, comma or period after it, are not part of it.
(String, String, String) _stripNonUrlBits(String fragment) {
  var prefix = '';
  var suffix = '';
  while (fragment.isNotEmpty) {
    if (fragment.startsWith('(')) {
      prefix = '$prefix(';
      fragment = fragment.substring(1);
      if (fragment.endsWith(')')) {
        suffix = ')$suffix';
        fragment = fragment.substring(0, fragment.length - 1);
      }
      continue;
    }
    if (fragment.endsWith(')') && !fragment.contains('(')) {
      fragment = fragment.substring(0, fragment.length - 1);
      suffix = ')$suffix';
      continue;
    }
    if (fragment.endsWith(',') || fragment.endsWith('.')) {
      suffix = '${fragment[fragment.length - 1]}$suffix';
      fragment = fragment.substring(0, fragment.length - 1);
      continue;
    }
    break;
  }
  return (fragment, prefix, suffix);
}
