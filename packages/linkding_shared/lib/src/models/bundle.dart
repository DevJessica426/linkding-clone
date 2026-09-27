import 'package:dust_dart/serde.dart';

import 'timestamps.dart';

part 'bundle.g.dart';

/// A saved search: bookmarks matching a phrase and a set of tag rules.
@Derive([ToString(), Eq(), CopyWith(), Serialize(), Deserialize()])
@SerDe(renameAll: SerDeRename.snakeCase)
final class Bundle with _$Bundle {
  const Bundle({
    required this.id,
    required this.name,
    required this.search,
    required this.anyTags,
    required this.allTags,
    required this.excludedTags,
    required this.filterUnread,
    required this.filterShared,
    required this.order,
    required this.dateCreated,
    required this.dateModified,
  });

  factory Bundle.fromJson(Map<String, Object?> json) => _$BundleFromJson(json);

  final int id;
  final String name;

  /// Words that must all appear, as in legacy search: no operators.
  final String search;

  /// Space-separated; a bookmark needs at least one of them.
  final String anyTags;

  /// Space-separated; a bookmark needs every one of them.
  final String allTags;

  /// Space-separated; a bookmark with any of them is left out.
  final String excludedTags;

  /// `off`, `yes` (unread only) or `no` (read only).
  final String filterUnread;

  /// `off`, `yes` (shared only) or `no` (unshared only).
  final String filterShared;

  /// Position in the sidebar, from 0.
  final int order;

  @SerDe(using: drfDateTime)
  final DateTime dateCreated;

  @SerDe(using: drfDateTime)
  final DateTime dateModified;
}

/// One page of `/api/bundles/`.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class BundlePage with _$BundlePage {
  const BundlePage({
    required this.count,
    required this.results,
    this.next,
    this.previous,
  });

  factory BundlePage.fromJson(Map<String, Object?> json) =>
      _$BundlePageFromJson(json);

  final int count;
  final String? next;
  final String? previous;
  final List<Bundle> results;
}
