import '../compat/django.dart';
import '../db/rows/rows.dart';
import 'netscape_bookmark.dart';

/// A bookmark's fields after `_copy_bookmark_data`.
typedef CopiedBookmark = ({
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
/// cannot be read. A bookmark without a date is added now, each at its own
/// moment.
CopiedBookmark? copyBookmarkData(
  NetscapeBookmark b,
  BookmarkRow? saved,
  bool mapPrivateFlag,
) {
  final added = (b.dateAdded ?? '').isNotEmpty
      ? parseTimestamp(b.dateAdded!)
      : DateTime.now().toUtc();
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
bool isValidBookmark(CopiedBookmark c, {required bool disableUrlValidation}) {
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
