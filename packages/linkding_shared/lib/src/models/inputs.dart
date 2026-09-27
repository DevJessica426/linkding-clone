import 'package:dust_dart/serde.dart';

part 'inputs.g.dart';

/// The body of `POST /api/bookmarks/` and `PUT /api/bookmarks/{id}/`.
///
/// Every field is sent. For a change to some fields only, send a map to
/// `PATCH`: linkding leaves any key that is absent untouched.
@Derive([ToString(), Eq(), CopyWith(), Serialize(), Deserialize()])
@SerDe(renameAll: SerDeRename.snakeCase)
final class BookmarkInput with _$BookmarkInput {
  const BookmarkInput({
    required this.url,
    this.title = '',
    this.description = '',
    this.notes = '',
    this.isArchived = false,
    this.unread = false,
    this.shared = false,
    this.tagNames = const [],
  });

  factory BookmarkInput.fromJson(Map<String, Object?> json) =>
      _$BookmarkInputFromJson(json);

  final String url;

  /// Left empty, the page's own title is used, unless scraping is disabled.
  final String title;

  /// Left empty, the page's own description is used, unless scraping is
  /// disabled.
  final String description;

  final String notes;
  final bool isArchived;
  final bool unread;
  final bool shared;
  final List<String> tagNames;
}

/// The body of `POST /api/tags/`.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class TagInput with _$TagInput {
  const TagInput({required this.name});

  factory TagInput.fromJson(Map<String, Object?> json) =>
      _$TagInputFromJson(json);

  final String name;
}

/// The body of `POST /api/bundles/` and `PUT /api/bundles/{id}/`.
@Derive([ToString(), Eq(), CopyWith(), Serialize(), Deserialize()])
@SerDe(renameAll: SerDeRename.snakeCase)
final class BundleInput with _$BundleInput {
  const BundleInput({
    required this.name,
    this.search = '',
    this.anyTags = '',
    this.allTags = '',
    this.excludedTags = '',
    this.filterUnread = 'off',
    this.filterShared = 'off',
    this.order,
  });

  factory BundleInput.fromJson(Map<String, Object?> json) =>
      _$BundleInputFromJson(json);

  final String name;
  final String search;
  final String anyTags;
  final String allTags;
  final String excludedTags;
  final String filterUnread;
  final String filterShared;

  /// Null places the bundle last.
  final int? order;
}
