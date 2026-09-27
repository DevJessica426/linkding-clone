import 'dart:io';

import 'package:dust_dart/db.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../core/auto_tagging.dart';
import '../core/profile.dart';
import '../core/urls.dart';
import '../db/bookmarks_repo.dart';
import '../db/database.dart';
import '../db/rows.dart';
import 'errors.dart';
import 'tags.dart';
import 'website_loader.dart';

/// The fields of a bookmark someone is saving, before it has an id.
final class BookmarkDraft {
  BookmarkDraft({
    required this.url,
    this.title = '',
    this.description = '',
    this.notes = '',
    this.isArchived = false,
    this.unread = false,
    this.shared = false,
    this.dateAdded,
    this.dateModified,
  });

  String url;
  String title;
  String description;
  String notes;
  bool isArchived;
  bool unread;
  bool shared;
  DateTime? dateAdded;
  DateTime? dateModified;
}

/// linkding's `services/bookmarks.py`.
final class BookmarkService {
  BookmarkService(this.database, this.metadata, {this.assetDir});

  final LinkdingDatabase database;
  final WebsiteMetadataLoader metadata;

  /// Where asset files live, to remove them with their bookmark.
  final String? assetDir;

  Connection get _db => database.connection;

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
    final repo = BookmarksRepo(_db);
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
      saved = await _transaction((tx) async {
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
        await _setTags(tx, inserted, tagString, ownerId, profile);
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
  ) => _transaction((tx) async {
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
    await _setTags(tx, row, tagString, ownerId, profile);
    return row;
  });

  /// `enhance_with_website_metadata`: fills an empty title and description
  /// from the page. `date_modified` is left alone.
  Future<BookmarkRow> enhanceWithMetadata(BookmarkRow row) async {
    if (row.title.isNotEmpty && row.description.isNotEmpty) return row;
    final page = await metadata.load(row.url);
    final title = row.title.isEmpty ? (page.title ?? '') : row.title;
    final description = row.description.isEmpty
        ? (page.description ?? '')
        : row.description;
    return (await BookmarksRepo(_db).update(
      row.id,
      row.url,
      row.urlNormalized,
      title,
      description,
      row.notes,
      row.unread,
      row.isArchived,
      row.shared,
      row.dateAdded,
      row.dateModified,
    )).orThrow;
  }

  /// `_update_bookmark_tags`: the tag string plus any automatic tags,
  /// replacing the bookmark's current tags.
  Future<void> _setTags(
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
    final repo = BookmarksRepo(tx);
    (await repo.unlinkOtherTags(row.id, ids)).orThrow;
    (await repo.linkTags(row.id, ids)).orThrow;
  }

  /// `archive_bookmark` / `unarchive_bookmark`.
  Future<void> setArchived(int ownerId, List<int> ids, bool archived) async =>
      (await BookmarksRepo(
        _db,
      ).setArchived(ownerId, ids, archived, DateTime.now().toUtc())).orThrow;

  Future<void> setUnread(int ownerId, List<int> ids, bool unread) async =>
      (await BookmarksRepo(
        _db,
      ).setUnread(ownerId, ids, unread, DateTime.now().toUtc())).orThrow;

  Future<void> setShared(int ownerId, List<int> ids, bool shared) async =>
      (await BookmarksRepo(
        _db,
      ).setShared(ownerId, ids, shared, DateTime.now().toUtc())).orThrow;

  /// Deletes the owner's bookmarks among [ids], with their tag links and
  /// assets, and removes the asset files.
  Future<void> delete(int ownerId, List<int> ids) async {
    for (final id in ids) {
      final files = (await BookmarksRepo(_db).delete(id, ownerId)).orThrow;
      _removeFiles(files.map((f) => f.file));
    }
  }

  /// `tag_bookmarks`: adds the tags in [tagString] to the owner's
  /// bookmarks among [ids].
  Future<void> tag(int ownerId, List<int> ids, String tagString) =>
      _transaction((tx) async {
        final repo = BookmarksRepo(tx);
        final owned = [
          for (final r in (await repo.ownedIds(ownerId, ids)).orThrow) r.id,
        ];
        final tags = await getOrCreateTags(
          tx,
          ownerId,
          parseTagString(tagString),
        );
        (await repo.linkAll(owned, [for (final t in tags) t.id])).orThrow;
        (await repo.touch(ownerId, owned, DateTime.now().toUtc())).orThrow;
      });

  /// `untag_bookmarks`.
  Future<void> untag(int ownerId, List<int> ids, String tagString) =>
      _transaction((tx) async {
        final repo = BookmarksRepo(tx);
        final owned = [
          for (final r in (await repo.ownedIds(ownerId, ids)).orThrow) r.id,
        ];
        final tags = await getOrCreateTags(
          tx,
          ownerId,
          parseTagString(tagString),
        );
        (await repo.unlinkAll(owned, [for (final t in tags) t.id])).orThrow;
        (await repo.touch(ownerId, owned, DateTime.now().toUtc())).orThrow;
      });

  /// Tag names for each of [ids], sorted as Python sorts strings.
  Future<Map<int, List<String>>> tagNames(List<int> ids) async {
    if (ids.isEmpty) return const {};
    final rows = (await BookmarksRepo(_db).tagNames(ids)).orThrow;
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

  Future<T> _transaction<T>(Future<T> Function(Executor tx) body) async {
    final result = await _db.transaction<T>((tx) async {
      try {
        return Ok(await body(tx));
      } on SqlxError catch (error) {
        return Err(error);
      }
    });
    return result.orThrow;
  }
}
