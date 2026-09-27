import 'dart:convert';
import 'dart:io';

import 'package:linkding_server/src/web/markdown.dart';
import 'package:test/test.dart';

/// Bookmark notes rendered as linkding's `{% markdown %}` tag renders them,
/// recorded by `tool/markdown_fixture.py`. Whitespace between tags, before
/// a closing tag and after a line break is not compared: it does not change
/// how a page looks.
void main() {
  final cases = (jsonDecode(
    File('test/fixtures/markdown.json').readAsStringSync(),
  ) as List<Object?>).cast<Map<String, Object?>>();

  String squeeze(String html) => html
      .replaceAll(RegExp(r'>\s+<'), '><')
      .replaceAll(RegExp(r'\s+</'), '</')
      .replaceAll(RegExp(r'<br>\s+'), '<br>')
      .trim();

  for (final c in cases) {
    final input = c['input']! as String;
    test(jsonEncode(input), () {
      expect(squeeze(renderNotes(input)), squeeze(c['html']! as String));
    });
  }
}
