import 'package:linkding_shared/linkding_shared.dart';

import '../compat/html_events.dart';
import '../core/urls.dart';
import 'netscape_bookmark.dart';

/// linkding's `parser.parse`, event for event: a `<DT>` or `</DL>` closes
/// the bookmark being read, an `<A>` starts one from its attributes, and
/// the text of the `<A>` and of a `<DD>` is its title and description.
List<NetscapeBookmark> parseNetscape(String source) {
  final bookmarks = <NetscapeBookmark>[];
  NetscapeBookmark? bookmark;
  // The parser's own attributes, all empty until an <A> overwrites them
  // with its own (null for an attribute without a value).
  Map<String, String?> reset() => {
    for (final name in const [
      'href',
      'add_date',
      'last_modified',
      'tags',
      'title',
      'description',
      'notes',
      'toread',
      'private',
    ])
      name: '',
  };
  var fields = reset();
  String? currentTag;

  void addBookmark() {
    final current = bookmark;
    if (current != null) {
      current
        ..title = fields['title'] ?? ''
        ..description = fields['description'] ?? ''
        ..notes = fields['notes'] ?? '';
      bookmarks.add(current);
    }
    bookmark = null;
    fields = reset();
  }

  for (final event in htmlEvents(source)) {
    switch (event) {
      case StartTag(:final name, :final attributes):
        if (name == 'dt') addBookmark();
        if (name == 'a') {
          for (final (key, value) in attributes) {
            fields[key] = value;
          }
          final tags = fields['tags'] ?? '';
          final tagNames = [...parseTagString(tags)]..remove(archivedTag);
          final href = fields['href'] ?? '';
          bookmark = NetscapeBookmark(
            href: href,
            hrefNormalized: normalizeUrl(href),
            dateAdded: fields['add_date'],
            dateModified: fields['last_modified'],
            tagNames: tagNames,
            toRead: fields['toread'] == '1',
            // Private unless the file says otherwise.
            private: fields['private'] != '0',
            archived: tags.contains(archivedTag),
          );
        }
        currentTag = name;
      case EndTag(:final name):
        if (name == 'dl') addBookmark();
        currentTag = null;
      case Text(:final data):
        if (currentTag == 'a') fields['title'] = data.trim();
        if (currentTag == 'dd') {
          final description = data.trim();
          final parts = description.split('[linkding-notes]');
          if (parts.length > 1) {
            fields['notes'] = parts[1].split('[/linkding-notes]').first;
          }
          fields['description'] = parts.first;
        }
    }
  }
  return bookmarks;
}
