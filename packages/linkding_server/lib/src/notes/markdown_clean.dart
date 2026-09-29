import 'package:html/dom.dart' as dom;

import 'markdown_escape.dart';
import 'markdown_linkify.dart';

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

/// Writes [node] as bleach's `clean` and then `linkify` would.
void cleanNode(
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
        referencePlaceholder,
        (m) => references[int.parse(m[1]!)],
      );
    }
    out.write(inLink ? escapeText(text) : linkify(text));
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
    cleanNode(
      dom.Text('<$tag$attributes>'),
      out,
      references,
      inLink: inLink,
      inCode: inCode,
    );
    for (final child in node.nodes) {
      cleanNode(child, out, references, inLink: inLink, inCode: inCode);
    }
    if (!_voidTags.contains(tag)) {
      cleanNode(
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
    linkCallbacks(attributes, node.text);
  }
  out.write('<$tag');
  attributes.forEach(
    (key, value) => out.write(' $key="${escapeAttribute(value)}"'),
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
      cleanNode(
        dom.Text(child.text.trimRight()),
        out,
        references,
        inLink: inLink,
        inCode: inCode,
      );
      continue;
    }
    cleanNode(
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

/// A character reference held back while Markdown runs: `\uE000`, its
/// number, `\uE001`.
final referencePlaceholder = RegExp('\uE000([0-9]+)\uE001');
