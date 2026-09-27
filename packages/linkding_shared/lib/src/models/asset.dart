import 'package:dust_dart/serde.dart';

import 'timestamps.dart';

part 'asset.g.dart';

/// A file attached to a bookmark, as `/api/bookmarks/<id>/assets/` returns
/// it: an uploaded file or an HTML snapshot of the page.
@Derive([ToString(), Eq(), CopyWith(), Serialize(), Deserialize()])
@SerDe(renameAll: SerDeRename.snakeCase)
final class BookmarkAsset with _$BookmarkAsset {
  const BookmarkAsset({
    required this.id,
    required this.bookmark,
    required this.dateCreated,
    required this.fileSize,
    required this.assetType,
    required this.contentType,
    required this.displayName,
    required this.status,
  });

  factory BookmarkAsset.fromJson(Map<String, Object?> json) =>
      _$BookmarkAssetFromJson(json);

  final int id;

  /// The bookmark's id.
  final int bookmark;

  @SerDe(using: drfDateTime)
  final DateTime dateCreated;

  /// Bytes on disk, compressed when the file is stored gzipped.
  final int? fileSize;

  /// `upload` or `snapshot`.
  final String assetType;
  final String contentType;
  final String displayName;

  /// `pending`, `complete` or `failure`.
  final String status;
}

/// One page of a bookmark's assets.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class BookmarkAssetPage with _$BookmarkAssetPage {
  const BookmarkAssetPage({
    required this.count,
    required this.results,
    this.next,
    this.previous,
  });

  factory BookmarkAssetPage.fromJson(Map<String, Object?> json) =>
      _$BookmarkAssetPageFromJson(json);

  final int count;
  final String? next;
  final String? previous;
  final List<BookmarkAsset> results;
}
