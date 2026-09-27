import 'package:dust_dart/db.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../compat/django.dart';
import '../compat/html_events.dart';
import '../core/urls.dart';
import '../db/bookmarks_repo.dart';
import '../db/rows.dart';
import '../db/tags_repo.dart';
import 'errors.dart';

/// A bookmark read from a Netscape bookmarks file: linkding's
/// `NetscapeBookmark`.
final class NetscapeBookmark {
  NetscapeBookmark({
    required this.href,
    required this.hrefNormalized,
    required this.dateAdded,
    required this.dateModified,
    required this.tagNames,
    required this.toRead,
    required this.private,
    required this.archived,
  });

  final String href;
  final String hrefNormalized;
  String title = '';
  String description = '';
  String notes = '';
  final String? dateAdded;
  final String? dateModified;
  final List<String> tagNames;
  final bool toRead;
  final bool private;
  final bool archived;
}

const _archivedTag = 'linkding:bookmarks.archived';

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
          final tagNames = [...parseTagString(tags)]..remove(_archivedTag);
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
            archived: tags.contains(_archivedTag),
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
      if (b.isArchived) _archivedTag,
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

/// What an import did.
final class ImportResult {
  int total = 0;
  int success = 0;
  int failed = 0;
  final importedUrls = <String>{};
}

/// linkding's `import_netscape_html`: tags first, then bookmarks in
/// batches of 200, updating those whose normalized URL is already saved.
Future<ImportResult> importNetscape(
  Executor db,
  String source,
  int ownerId, {
  required bool mapPrivateFlag,
  required bool disableUrlValidation,
}) async {
  final result = ImportResult();
  final parsed = parseNetscape(source);
  final tags = TagsRepo(db);

  // The tag cache: every tag of the owner by lowercase name, the later one
  // winning.
  Future<Map<String, TagRow>> tagCache() async => {
    for (final tag in (await tags.all(ownerId)).orThrow)
      tag.name.toLowerCase(): tag,
  };

  var cache = await tagCache();
  final now = DateTime.now().toUtc();
  for (final bookmark in parsed) {
    for (final name in bookmark.tagNames) {
      if (name.runes.length > 64) continue;
      if (cache.containsKey(name.toLowerCase())) continue;
      cache[name.toLowerCase()] = (await tags.insert(
        name,
        now,
        ownerId,
      )).orThrow;
    }
  }
  cache = await tagCache();

  final repo = BookmarksRepo(db);
  for (var offset = 0; offset < parsed.length; offset += 200) {
    final batch = parsed.sublist(
      offset,
      offset + 200 > parsed.length ? parsed.length : offset + 200,
    );
    final urls = [for (final b in batch) b.hrefNormalized];
    final existing = (await repo.withNormalizedUrls(ownerId, urls)).orThrow;
    final imported = <NetscapeBookmark>[];
    final updates = <(BookmarkRow, _Copied)>[];
    final creates = <_Copied>[];

    for (final bookmark in batch) {
      result.total++;
      if (result.importedUrls.contains(bookmark.hrefNormalized)) {
        result.failed++;
        continue;
      }
      final saved = existing
          .where((b) => b.urlNormalized == bookmark.hrefNormalized)
          .firstOrNull;
      final copied = _copy(bookmark, saved, mapPrivateFlag, now);
      if (copied == null ||
          !_valid(copied, disableUrlValidation: disableUrlValidation)) {
        result.failed++;
        continue;
      }
      if (saved != null) {
        updates.add((saved, copied));
      } else {
        creates.add(copied);
      }
      result.success++;
      result.importedUrls.add(bookmark.hrefNormalized);
      imported.add(bookmark);
    }

    for (final (saved, c) in updates) {
      (await repo.importUpdate(
        saved.id,
        c.url,
        c.urlNormalized,
        c.dateAdded,
        c.dateModified,
        c.unread,
        c.shared,
        c.title,
        c.description,
        c.notes,
      )).orThrow;
    }
    for (final c in creates) {
      (await repo.insert(
        c.url,
        c.urlNormalized,
        c.title,
        c.description,
        c.notes,
        c.unread,
        c.isArchived,
        c.shared,
        c.dateAdded,
        c.dateModified,
        ownerId,
      )).orThrow;
    }

    final saved = (await repo.withNormalizedUrls(ownerId, urls)).orThrow;
    for (final bookmark in imported) {
      final row = saved
          .where((b) => b.urlNormalized == bookmark.hrefNormalized)
          .firstOrNull;
      if (row == null) continue;
      final tagIds = <int>[];
      for (final name in bookmark.tagNames) {
        final tag = cache[name.toLowerCase()];
        if (tag != null && !tagIds.contains(tag.id)) tagIds.add(tag.id);
      }
      if (tagIds.isNotEmpty) (await repo.linkTags(row.id, tagIds)).orThrow;
    }
  }
  return result;
}

/// A bookmark's fields after `_copy_bookmark_data`.
typedef _Copied = ({
  String url,
  String urlNormalized,
  DateTime dateAdded,
  DateTime dateModified,
  bool unread,
  bool shared,
  bool isArchived,
  String title,
  String description,
  String notes,
});

/// `_copy_bookmark_data` onto [saved] or a new bookmark; null when a date
/// cannot be read.
_Copied? _copy(
  NetscapeBookmark b,
  BookmarkRow? saved,
  bool mapPrivateFlag,
  DateTime now,
) {
  final added = (b.dateAdded ?? '').isNotEmpty
      ? parseTimestamp(b.dateAdded!)
      : now;
  if (added == null) return null;
  final modified = (b.dateModified ?? '').isNotEmpty
      ? parseTimestamp(b.dateModified!)
      : added;
  if (modified == null) return null;
  return (
    url: b.href,
    urlNormalized: b.hrefNormalized,
    dateAdded: added,
    dateModified: modified,
    unread: b.toRead,
    shared: (mapPrivateFlag && !b.private) || (saved?.shared ?? false),
    isArchived: b.archived || (saved?.isArchived ?? false),
    title: b.title.isNotEmpty ? b.title : saved?.title ?? '',
    description: b.description.isNotEmpty
        ? b.description
        : saved?.description ?? '',
    notes: b.notes.isNotEmpty ? b.notes : saved?.notes ?? '',
  );
}

/// The model's `clean_fields` for what an import sets.
bool _valid(_Copied c, {required bool disableUrlValidation}) {
  if (c.url.isEmpty || c.url.runes.length > 2048) return false;
  if (!disableUrlValidation && !isValidUrl(c.url)) return false;
  if (c.urlNormalized.runes.length > 2048) return false;
  return c.title.runes.length <= 512;
}

/// linkding's `parse_timestamp`: seconds, else milliseconds, else
/// microseconds since the epoch, whichever gives a date Python can hold
/// (years 1 to 9999); null for anything else.
DateTime? parseTimestamp(String value) {
  final text = value.trim();
  if (!RegExp(r'^[+-]?\d+(_\d+)*$').hasMatch(text)) return null;
  final timestamp = BigInt.parse(text.replaceAll('_', ''));
  final min = BigInt.from(-62135596800);
  final max = BigInt.from(253402300799);
  for (final divisor in [1, 1000, 1000000]) {
    final d = BigInt.from(divisor);
    // Python divides as floats; whole microseconds are close enough.
    final micros = timestamp * BigInt.from(1000000) ~/ d;
    final seconds = timestamp ~/ d;
    if (seconds >= min && seconds <= max) {
      return DateTime.fromMicrosecondsSinceEpoch(micros.toInt(), isUtc: true);
    }
  }
  return null;
}
