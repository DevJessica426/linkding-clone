import 'package:dust_server/server.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../config.dart';
import '../core/auto_tagging.dart';
import '../core/urls.dart';
import '../db/bookmarks_repo.dart';
import '../db/rows.dart';
import '../services/bookmarks.dart';
import '../services/errors.dart';
import '../services/website_loader.dart';
import 'body.dart';
import 'bookmark_fields.dart';
import 'bookmark_json.dart';
import 'errors.dart';
import 'lookups.dart';

/// The caller's bookmark named in the path: 404 for anyone else's.
Future<BookmarkRow> ownedBookmark(Request request, UserRow user) async {
  final id = await pathId(request, 'Bookmark');
  final row = (await BookmarksRepo(
    await apiDb(request),
  ).owned(id, user.id)).orThrow;
  if (row == null) throw ApiException.noMatch('Bookmark');
  return row;
}

/// `GET /api/`, which lists nothing.
Future<Response> apiIndex(Request request) async =>
    apiJson(const <String, Object?>{});

/// `GET /api/bookmarks/<id>/`.
Future<Response> retrieveBookmark(Request request) async => apiJson(
  await serializeBookmark(
    request,
    await ownedBookmark(request, await apiUserOf(request)),
  ),
);

/// `GET /api/bookmarks/check/?url=`.
Future<Response> checkBookmark(Request request) async {
  final db = await apiDb(request);
  final user = await apiUserOf(request);
  final query = request.requestedUri.queryParameters;
  final url = query['url'];
  final existing = (await BookmarksRepo(
    db,
  ).existing(user.id, normalizeUrl(url), url ?? '')).orThrow;
  final page = await (await request.state<WebsiteMetadataLoader>()).load(
    url,
    ignoreCache: query['ignore_cache'] == 'true',
  );
  final profile = await profileOf(db, user.id);
  var tags = const <String>[];
  if (profile.autoTaggingRules.isNotEmpty && url != null) {
    try {
      tags = autoTags(profile.autoTaggingRules, url).toList()..sort();
    } on AutoTaggingError {
      // no automatic tags, as in linkding
    }
  }
  return apiJson({
    'bookmark': existing == null
        ? null
        : await serializeBookmark(request, existing),
    'metadata': page.toJson(),
    'auto_tags': tags,
  });
}

/// `POST /api/bookmarks/`: creates, or updates the bookmark already saved
/// for the URL. `201` either way, with the URL as `Location`.
Future<Response> createBookmark(Request request) async {
  final config = await request.state<ServerConfig>();
  final user = await apiUserOf(request);
  final fields = bookmarkFields(
    await readRequestBody(request),
    partial: false,
    checkUrl: !config.disableUrlValidation,
  );
  final saved = await (await request.state<BookmarkService>()).create(
    BookmarkDraft(
      url: fields.url!,
      title: fields.title ?? '',
      description: fields.description ?? '',
      notes: fields.notes ?? '',
      isArchived: fields.isArchived ?? false,
      unread: fields.unread ?? false,
      shared: fields.shared ?? false,
      dateAdded: fields.dateAdded,
      dateModified: fields.dateModified,
    ),
    buildTagString(fields.tagNames ?? const []),
    user.id,
    await profileOf(await apiDb(request), user.id),
    scrape:
        config.enableMetadataScraping &&
        !request.requestedUri.queryParameters.containsKey('disable_scraping'),
  );
  return apiJson(
    await serializeBookmark(request, saved),
    status: 201,
    headers: {'location': saved.url},
  );
}

/// `PUT /api/bookmarks/<id>/`: fields not sent keep their values.
Future<Response> replaceBookmark(Request request) =>
    _update(request, partial: false);

/// `PATCH /api/bookmarks/<id>/`.
Future<Response> patchBookmark(Request request) =>
    _update(request, partial: true);

Future<Response> _update(Request request, {required bool partial}) async {
  final db = await apiDb(request);
  final config = await request.state<ServerConfig>();
  final bookmarks = await request.state<BookmarkService>();
  final user = await apiUserOf(request);
  final row = await ownedBookmark(request, user);
  final fields = bookmarkFields(
    await readRequestBody(request),
    partial: partial,
    checkUrl: !config.disableUrlValidation,
  );
  if (fields.url != null &&
      (await BookmarksRepo(
        db,
      ).urlTaken(user.id, fields.url!, row.id)).orThrow) {
    throw ApiException.invalid({
      'url': ['A bookmark with this URL already exists.'],
    });
  }
  final current = (await bookmarks.tagNames([row.id]))[row.id] ?? const [];
  final saved = await bookmarks.update(
    row.id,
    BookmarkDraft(
      url: fields.url ?? row.url,
      title: fields.title ?? row.title,
      description: fields.description ?? row.description,
      notes: fields.notes ?? row.notes,
      isArchived: fields.isArchived ?? row.isArchived,
      unread: fields.unread ?? row.unread,
      shared: fields.shared ?? row.shared,
      dateAdded: fields.dateAdded ?? row.dateAdded,
    ),
    buildTagString(fields.tagNames ?? current),
    user.id,
    await profileOf(db, user.id),
  );
  return apiJson(await serializeBookmark(request, saved));
}

/// `POST /api/bookmarks/<id>/archive/`.
Future<Response> archiveBookmark(Request request) =>
    _archive(request, archived: true);

/// `POST /api/bookmarks/<id>/unarchive/`.
Future<Response> unarchiveBookmark(Request request) =>
    _archive(request, archived: false);

Future<Response> _archive(Request request, {required bool archived}) async {
  final user = await apiUserOf(request);
  final row = await ownedBookmark(request, user);
  await (await request.state<BookmarkService>()).setArchived(user.id, [
    row.id,
  ], archived);
  return Response(204);
}

/// `DELETE /api/bookmarks/<id>/`.
Future<Response> deleteBookmark(Request request) async {
  final user = await apiUserOf(request);
  final row = await ownedBookmark(request, user);
  await (await request.state<BookmarkService>()).delete(user.id, [row.id]);
  return Response(204);
}
