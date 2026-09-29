import 'package:linkding_shared/linkding_shared.dart';

import '../compat/form_data.dart';
import '../db/rows.dart';
import '../db/tags_repo.dart';
import '../pages/cleaning.dart';
import '../services/errors.dart';

/// The user's tag with the id in [id], or null (not a number, too large,
/// or not theirs).
Future<TagRow?> ownedTag(TagsRepo tags, String? id, int ownerId) async {
  final tagId = int.tryParse(id ?? '');
  if (tagId == null || tagId > 2147483647) return null;
  return (await tags.owned(tagId, ownerId)).orThrow;
}

/// `TagForm.clean_name` and the model's length limit: the name to save, and
/// its errors.
Future<(String, List<String>)> cleanTagName(
  TagsRepo tags,
  String? raw,
  int ownerId, {
  int? except,
}) async {
  final field = cleanChar(raw, required: true);
  if (field.errors.isNotEmpty) return ('', field.errors);
  final name = sanitizeTagName(field.value);
  final existing = (await tags.named(ownerId, name)).orThrow;
  if (existing != null && existing.id != except) {
    return (name, ['Tag "$name" already exists.']);
  }
  return (name, cleanChar(name, maxLength: 64).errors);
}

/// `MergeTagsForm`: the tag to keep, the tags to merge into it, and each
/// field's errors.
final class MergeForm {
  TagRow? target;
  final merged = <TagRow>[];
  final errors = <String, List<String>>{'target_tag': [], 'merge_tags': []};

  bool get isValid => errors.values.every((e) => e.isEmpty);
}

Future<MergeForm> cleanMerge(TagsRepo tags, FormData form, int ownerId) async {
  final result = MergeForm();
  final targetErrors = result.errors['target_tag']!;
  final targetField = cleanChar(form['target_tag'], required: true);
  targetErrors.addAll(targetField.errors);
  if (targetField.errors.isEmpty) {
    final names = parseTagString(targetField.value, delimiter: ' ');
    if (names.length != 1) {
      targetErrors.add('Please enter only one tag name for the target tag.');
    } else {
      result.target = (await tags.named(ownerId, names.single)).orThrow;
      if (result.target == null) {
        targetErrors.add('Tag "${names.single}" does not exist.');
      }
    }
  }
  final mergeErrors = result.errors['merge_tags']!;
  final mergeField = cleanChar(form['merge_tags'], required: true);
  mergeErrors.addAll(mergeField.errors);
  if (mergeField.errors.isNotEmpty) return result;
  final names = parseTagString(mergeField.value, delimiter: ' ');
  if (names.isEmpty) mergeErrors.add('Please enter at least one tag to merge.');
  for (final name in names) {
    final tag = (await tags.named(ownerId, name)).orThrow;
    if (tag == null) {
      mergeErrors.add('Tag "$name" does not exist.');
      break;
    }
    result.merged.add(tag);
  }
  final target = result.target;
  if (mergeErrors.isEmpty &&
      target != null &&
      result.merged.any((t) => t.id == target.id)) {
    mergeErrors.add('The target tag cannot be selected for merging.');
  }
  return result;
}
