import 'package:dust_dart/serde.dart';

import 'timestamps.dart';

part 'tag.g.dart';

/// A tag as `/api/tags/` returns it.
@Derive([ToString(), Eq(), CopyWith(), Serialize(), Deserialize()])
@SerDe(renameAll: SerDeRename.snakeCase)
final class Tag with _$Tag {
  const Tag({required this.id, required this.name, required this.dateAdded});

  factory Tag.fromJson(Map<String, Object?> json) => _$TagFromJson(json);

  final int id;

  /// Unique per owner, ignoring case.
  final String name;

  @SerDe(using: drfDateTime)
  final DateTime dateAdded;
}

/// One page of `/api/tags/`.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class TagPage with _$TagPage {
  const TagPage({
    required this.count,
    required this.results,
    this.next,
    this.previous,
  });

  factory TagPage.fromJson(Map<String, Object?> json) =>
      _$TagPageFromJson(json);

  final int count;
  final String? next;
  final String? previous;
  final List<Tag> results;
}
