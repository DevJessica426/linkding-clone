import 'package:dust_dart/db.dart';

import '../db/rows.dart';
import '../db/tags_repo.dart';
import 'errors.dart';

/// linkding's `get_or_create_tag`: the owner's tag with this name in any
/// case, or a new one spelled as given.
Future<TagRow> getOrCreateTag(Executor db, int ownerId, String name) async {
  final tags = TagsRepo(db);
  final existing = (await tags.named(ownerId, name)).orThrow;
  if (existing != null) return existing;
  return (await tags.insert(name, DateTime.now().toUtc(), ownerId)).orThrow;
}

/// linkding's `get_or_create_tags`: one tag per name, duplicates by id
/// removed, keeping the order of the last occurrence as Python's dict does.
Future<List<TagRow>> getOrCreateTags(
  Executor db,
  int ownerId,
  Iterable<String> names,
) async {
  final byId = <int, TagRow>{};
  for (final name in names) {
    final tag = await getOrCreateTag(db, ownerId, name);
    byId[tag.id] = tag;
  }
  return byId.values.toList();
}
