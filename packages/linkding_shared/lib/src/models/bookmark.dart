import 'package:dust_dart/serde.dart';

import 'timestamps.dart';

part 'bookmark.g.dart';

/// A bookmark as `/api/bookmarks/` returns it.
@Derive([ToString(), Eq(), CopyWith(), Serialize(), Deserialize()])
@SerDe(renameAll: SerDeRename.snakeCase)
final class Bookmark with _$Bookmark {
  const Bookmark({
    required this.id,
    required this.url,
    required this.title,
    required this.description,
    required this.notes,
    required this.isArchived,
    required this.unread,
    required this.shared,
    required this.tagNames,
    required this.dateAdded,
    required this.dateModified,
    this.webArchiveSnapshotUrl,
    this.faviconUrl,
    this.previewImageUrl,
    this.websiteTitle,
    this.websiteDescription,
  });

  factory Bookmark.fromJson(Map<String, Object?> json) =>
      _$BookmarkFromJson(json);

  final int id;
  final String url;
  final String title;
  final String description;

  /// Markdown.
  final String notes;

  /// The stored Internet Archive snapshot, or a link to the archive's copy
  /// closest to [dateAdded] when none was stored.
  final String? webArchiveSnapshotUrl;

  final String? faviconUrl;
  final String? previewImageUrl;
  final bool isArchived;
  final bool unread;
  final bool shared;

  /// Sorted by code point, as linkding sorts them.
  final List<String> tagNames;

  @SerDe(using: drfDateTime)
  final DateTime dateAdded;

  @SerDe(using: drfDateTime)
  final DateTime dateModified;

  /// Always null. linkding keeps both keys for older clients.
  final String? websiteTitle;

  /// Always null. linkding keeps both keys for older clients.
  final String? websiteDescription;
}

/// One page of `/api/bookmarks/`, `/archived/` or `/shared/`.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class BookmarkPage with _$BookmarkPage {
  const BookmarkPage({
    required this.count,
    required this.results,
    this.next,
    this.previous,
  });

  factory BookmarkPage.fromJson(Map<String, Object?> json) =>
      _$BookmarkPageFromJson(json);

  /// Every match, not just this page.
  final int count;

  /// The absolute URL of the next page, or null on the last one.
  final String? next;

  /// The absolute URL of the previous page, or null on the first one.
  final String? previous;

  final List<Bookmark> results;
}

/// What `/api/bookmarks/check/` scraped from the page itself.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
@SerDe(renameAll: SerDeRename.snakeCase)
final class WebsiteMetadata with _$WebsiteMetadata {
  const WebsiteMetadata({
    this.url,
    this.title,
    this.description,
    this.previewImage,
  });

  factory WebsiteMetadata.fromJson(Map<String, Object?> json) =>
      _$WebsiteMetadataFromJson(json);

  /// The URL that was checked; null when `check` was called without one.
  final String? url;

  final String? title;
  final String? description;
  final String? previewImage;
}

/// `GET /api/bookmarks/check/?url=`: whether a URL is already saved, and
/// what saving it would start from.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
@SerDe(renameAll: SerDeRename.snakeCase)
final class CheckResult with _$CheckResult {
  const CheckResult({
    required this.metadata,
    required this.autoTags,
    this.bookmark,
  });

  factory CheckResult.fromJson(Map<String, Object?> json) =>
      _$CheckResultFromJson(json);

  /// The saved bookmark for this URL, compared after normalizing both.
  final Bookmark? bookmark;

  final WebsiteMetadata metadata;

  /// Tags the owner's auto-tagging rules would add. linkding computes a set,
  /// so the order carries no meaning.
  final List<String> autoTags;
}
