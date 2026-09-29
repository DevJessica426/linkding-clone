import 'dart:io';

import 'package:dust_dart/db.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../../core/auto_tagging.dart';
import '../../core/profile.dart';
import '../../db/repos/bookmark_tags_repo.dart';
import '../../db/or_throw.dart';
import '../../db/rows/rows.dart';
import '../../tags/tag_service.dart';

/// `_update_bookmark_tags`: the tag string plus any automatic tags,
/// replacing the bookmark's current tags.
Future<void> replaceBookmarkTags(
  Executor tx,
  BookmarkRow row,
  String tagString,
  int ownerId,
  Profile profile,
) async {
  final names = parseTagString(tagString);
  if (profile.autoTaggingRules.isNotEmpty) {
    try {
      for (final name in autoTags(profile.autoTaggingRules, row.url)) {
        if (!names.contains(name)) names.add(name);
      }
    } on AutoTaggingError catch (error) {
      stderr.writeln('Failed to auto-tag bookmark. url=${row.url}: $error');
    }
  }
  final tags = await getOrCreateTags(tx, ownerId, names);
  final ids = [for (final tag in tags) tag.id];
  final links = BookmarkTagsRepo(tx);
  (await links.unlinkOtherTags(row.id, ids)).orThrow;
  (await links.linkTags(row.id, ids)).orThrow;
}
