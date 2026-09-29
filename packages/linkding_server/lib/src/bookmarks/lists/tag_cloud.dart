import '../../db/rows/rows.dart';

/// A tag cloud group: tags sharing a first letter, or all of them.
final class TagGroup {
  TagGroup(this.char, {this.highlightFirstChar = true});

  final String char;
  final bool highlightFirstChar;
  final List<String> tags = [];
}

final _cjk = RegExp(r'^[一-鿿]');

/// `TagGroup.create_tag_groups`.
List<TagGroup> tagGroups(String mode, Iterable<String> names) {
  final sorted = names.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  if (mode != 'alphabetical') {
    if (sorted.isEmpty) return const [];
    return [
      TagGroup('Ungrouped', highlightFirstChar: false)..tags.addAll(sorted),
    ];
  }
  final groups = <TagGroup>[];
  final cjk = TagGroup('Ideographic');
  for (final name in sorted) {
    final char = String.fromCharCode(name.runes.first).toLowerCase();
    if (_cjk.hasMatch(char)) {
      cjk.tags.add(name);
    } else if (groups.isEmpty || groups.last.char != char) {
      groups.add(TagGroup(char)..tags.add(name));
    } else {
      groups.last.tags.add(name);
    }
  }
  if (cjk.tags.isNotEmpty) groups.add(cjk);
  return groups;
}

/// `TagCloudContext`: the tags of every match, less the ones the search
/// already names, which are listed to remove instead.
final class TagCloud {
  TagCloud(this.groups, this.selected);

  /// [candidateTags] are the tags on the matches, [selectedTags] the tags
  /// the query names; both are compared by name ignoring case, keeping the
  /// last of each, and by identity for what is left.
  factory TagCloud.of(
    String grouping,
    List<BookmarkTagRow> candidateTags,
    List<TagRow> selectedTags,
  ) {
    final unique = <String, (int, String)>{};
    final byId = {for (final t in candidateTags) t.tagId: t}.values.toList()
      ..sort((a, b) => a.tagId.compareTo(b.tagId));
    for (final tag in byId) {
      unique[tag.name.toLowerCase()] = (tag.tagId, tag.name);
    }
    final selected = <String, (int, String)>{};
    for (final tag in selectedTags) {
      selected[tag.name.toLowerCase()] = (tag.id, tag.name);
    }
    final uniqueIds = {for (final t in unique.values) t.$1};
    final selectedIds = {for (final t in selected.values) t.$1};
    final unselected = [
      for (final t in unique.values)
        if (!selectedIds.contains(t.$1)) t.$2,
      for (final t in selected.values)
        if (!uniqueIds.contains(t.$1)) t.$2,
    ];
    return TagCloud(tagGroups(grouping, unselected), [
      for (final t in selected.values) t.$2,
    ]);
  }

  final List<TagGroup> groups;
  final List<String> selected;
}
