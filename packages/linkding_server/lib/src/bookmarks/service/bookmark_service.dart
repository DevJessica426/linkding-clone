import 'dart:io';

import 'package:dust_dart/db.dart';

import '../../core/profile.dart';
import '../../core/urls.dart';
import '../../db/repos/bookmark_tags_repo.dart';
import '../../db/repos/bookmarks_repo.dart';
import '../../db/database.dart';
import '../../db/or_throw.dart';
import '../../db/rows/rows.dart';
import '../../metadata/website_loader.dart';
import 'bookmark_draft.dart';
import 'bookmark_metadata.dart';
import 'bookmark_tagging.dart';

export 'bookmark_bulk.dart';
export 'bookmark_draft.dart';
export 'bookmark_metadata.dart';

/// linkding's `services/bookmarks.py`.
final class BookmarkService {
  BookmarkService(this.database, this.metadata, {this.assetDir});

  final LinkdingDatabase database;
  final WebsiteMetadataLoader metadata;

  /// Where asset files live, to remove them with their bookmark.
  final String? assetDir;

  Connection get db => database.connection;

  /// `create_bookmark`. A URL the owner already saved (compared normalized)
  /// updates that bookmark instead: title, description, notes, unread and
  /// shared are taken from [draft], tags replaced, archive state kept.
  Future<BookmarkRow> create(
    BookmarkDraft draft,
    String tagString,
    int ownerId,
    Profile profile, {
    bool scrape = true,
  }) async {
    final repo = BookmarksRepo(db);
    final existing = (await repo.existing(
      ownerId,
      normalizeUrl(draft.url),
      draft.url,
    )).orThrow;

    BookmarkRow saved;
    if (existing != null) {
      final merged = BookmarkDraft(
        url: existing.url,
        title: draft.title,
        description: draft.description,
        notes: draft.notes,
        isArchived: existing.isArchived,
        unread: draft.unread,
        shared: draft.shared,
        dateAdded: existing.dateAdded,
      );
      saved = await update(existing.id, merged, tagString, ownerId, profile);
    } else {
      final now = DateTime.now().toUtc();
      saved = await transaction((tx) async {
        final inserted = (await BookmarksRepo(tx).insert(
          draft.url,
          normalizeUrl(draft.url),
          draft.title,
          draft.description,
          draft.notes,
          draft.unread,
          draft.isArchived,
          draft.shared,
          draft.dateAdded ?? now,
          draft.dateModified ?? now,
          ownerId,
        )).orThrow;
        await replaceBookmarkTags(tx, inserted, tagString, ownerId, profile);
        return inserted;
      });
    }
    if (scrape) saved = await enhanceWithMetadata(saved);
    return saved;
  }

  /// `update_bookmark`: saves [draft] over bookmark [id], replaces its tags
  /// and moves `date_modified` to now.
  Future<BookmarkRow> update(
    int id,
    BookmarkDraft draft,
    String tagString,
    int ownerId,
    Profile profile,
  ) => transaction((tx) async {
    final row = (await BookmarksRepo(tx).update(
      id,
      draft.url,
      normalizeUrl(draft.url),
      draft.title,
      draft.description,
      draft.notes,
      draft.unread,
      draft.isArchived,
      draft.shared,
      draft.dateAdded!,
      DateTime.now().toUtc(),
    )).orThrow;
    await replaceBookmarkTags(tx, row, tagString, ownerId, profile);
    return row;
  });

  /// Deletes the owner's bookmarks among [ids], with their tag links and
  /// assets, and removes the asset files.
  Future<void> delete(int ownerId, List<int> ids) async {
    for (final id in ids) {
      final files = (await BookmarksRepo(db).delete(id, ownerId)).orThrow;
      _removeFiles(files.map((f) => f.file));
    }
  }

  /// Tag names for each of [ids], sorted as Python sorts strings.
  Future<Map<int, List<String>>> tagNames(List<int> ids) async {
    if (ids.isEmpty) return const {};
    final rows = (await BookmarkTagsRepo(db).tagNames(ids)).orThrow;
    final byBookmark = <int, List<String>>{};
    for (final row in rows) {
      (byBookmark[row.bookmarkId] ??= []).add(row.name);
    }
    for (final names in byBookmark.values) {
      names.sort();
    }
    return byBookmark;
  }

  void _removeFiles(Iterable<String> files) {
    final dir = assetDir;
    if (dir == null) return;
    for (final file in files) {
      if (file.isEmpty) continue;
      try {
        final path = File('$dir/$file');
        if (path.existsSync()) path.deleteSync();
      } on FileSystemException catch (error) {
        stderr.writeln('Failed to delete asset file: $file: $error');
      }
    }
  }

  Future<T> transaction<T>(Future<T> Function(Executor tx) body) async {
    final result = await db.transaction<T>((tx) async {
      try {
        return Ok(await body(tx));
      } on SqlxError catch (error) {
        return Err(error);
      }
    });
    return result.orThrow;
  }
}
