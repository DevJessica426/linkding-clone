import '../db/rows/rows.dart';
import 'netscape_bookmark.dart';

/// Python's `html.escape`.
String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#x27;');

/// linkding's `export_netscape_html`; lines are joined with `\n\r`, as
/// linkding joins them.
String exportNetscape(
  List<BookmarkRow> bookmarks,
  Map<int, List<String>> tagNames,
) {
  final doc = <String>[
    '<!DOCTYPE NETSCAPE-Bookmark-file-1>',
    '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
    '<TITLE>Bookmarks</TITLE>',
    '<H1>Bookmarks</H1>',
    '<DL><p>',
  ];
  for (final b in bookmarks) {
    final title = _escape(b.title.isNotEmpty ? b.title : b.url);
    var description = _escape(b.description);
    if (b.notes.isNotEmpty) {
      description += '[linkding-notes]${_escape(b.notes)}[/linkding-notes]';
    }
    final tags = [
      ...(tagNames[b.id] ?? const <String>[]),
      if (b.isArchived) archivedTag,
    ].map(_escape).join(',');
    final added = b.dateAdded.microsecondsSinceEpoch ~/ 1000000;
    final modified = b.dateModified.microsecondsSinceEpoch ~/ 1000000;
    doc.add(
      '<DT><A HREF="${b.url}" ADD_DATE="$added" LAST_MODIFIED="$modified" '
      'PRIVATE="${b.shared ? 0 : 1}" TOREAD="${b.unread ? 1 : 0}" '
      'TAGS="$tags">$title</A>',
    );
    if (description.isNotEmpty) doc.add('<DD>$description');
  }
  doc.add('</DL><p>');
  return doc.join('\n\r');
}
