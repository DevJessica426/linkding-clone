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

/// The tag linkding puts on archived bookmarks in an export.
const archivedTag = 'linkding:bookmarks.archived';
