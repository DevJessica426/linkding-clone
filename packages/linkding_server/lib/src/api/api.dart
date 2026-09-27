import 'package:dust_server/server.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../auth/sessions.dart';
import '../config.dart';
import '../core/auto_tagging.dart';
import '../core/profile.dart';
import '../core/urls.dart';
import '../db/bookmarks_repo.dart';
import '../db/bundles_repo.dart';
import '../db/database.dart';
import '../db/rows.dart';
import '../db/settings_repo.dart';
import '../db/tags_repo.dart';
import '../db/users_repo.dart';
import '../services/bookmarks.dart';
import '../services/errors.dart';
import '../services/search.dart';
import '../services/tags.dart';
import '../services/website_loader.dart';
import 'authentication.dart';
import 'pagination.dart';
import 'requests.dart';

typedef _Handler = Future<Response> Function(Request request, UserRow? user);

/// linkding's REST API under `/api`, at linkding's paths.
final class LinkdingApi {
  LinkdingApi({
    required this.database,
    required this.bookmarks,
    required this.metadata,
    required this.sessions,
    required this.config,
  });

  final LinkdingDatabase database;
  final BookmarkService bookmarks;
  final WebsiteMetadataLoader metadata;
  final Sessions sessions;
  final ServerConfig config;

  // One path segment without a dot, as DRF's router matches ids. The slash is
  // written as `\x2f`: dust_server never matches a pattern containing `/`.
  static const _id = r'{id|[^.\x2f]+}';

  /// Every route, each with the slash-less form redirecting to it as
  /// Django's `APPEND_SLASH` does.
  Router router() {
    final routes = <String, Map<String, _Handler>>{
      '/bookmarks/': {'GET': _listActive, 'POST': _create},
      '/bookmarks/archived/': {'GET': _listArchived},
      '/bookmarks/shared/': {'GET': _listShared},
      '/bookmarks/check/': {'GET': _check},
      '/bookmarks/$_id/': {
        'GET': _retrieve,
        'PUT': (r, u) => _update(r, u!, partial: false),
        'PATCH': (r, u) => _update(r, u!, partial: true),
        'DELETE': _delete,
      },
      '/bookmarks/$_id/archive/': {'POST': (r, u) => _archive(r, u!, true)},
      '/bookmarks/$_id/unarchive/': {'POST': (r, u) => _archive(r, u!, false)},
      '/tags/': {'GET': _listTags, 'POST': _createTag},
      '/tags/$_id/': {'GET': _retrieveTag, 'DELETE': _deleteTag},
      '/bundles/': {'GET': _listBundles, 'POST': _createBundle},
      '/bundles/$_id/': {
        'GET': _retrieveBundle,
        'PUT': (r, u) => _updateBundle(r, u!, partial: false),
        'PATCH': (r, u) => _updateBundle(r, u!, partial: true),
        'DELETE': _deleteBundle,
      },
      '/user/profile/': {'GET': _profile},
    };
    final router = Router();
    for (final MapEntry(key: path, value: methods) in routes.entries) {
      router.route(
        path,
        any(_view(methods, anonymous: path == '/bookmarks/shared/')),
      );
      router.route(path.substring(0, path.length - 1), any(_appendSlash));
    }
    return router;
  }

  /// `/api/` itself, which lists nothing. Mounted by the app, because a
  /// nested router's own root has no trailing slash.
  Endpoint<Response> get root => _view({'GET': _root});

  /// Django's `APPEND_SLASH` redirect, for mounting beside [root].
  static Response appendSlash(Request request) => _appendSlash(request);

  /// One DRF view: authenticate, then pick the method (or 405), then run.
  Endpoint<Response> _view(
    Map<String, _Handler> methods, {
    bool anonymous = false,
  }) {
    // Every DRF response names the methods its view serves, in this order.
    const order = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];
    final allowed = {
      ...methods.keys,
      if (methods.containsKey('GET')) 'HEAD',
      'OPTIONS',
    }.toList()..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    final allow = {'allow': allowed.join(', ')};

    return (request) async {
      Response response;
      try {
        final user = await apiUser(request, database.connection, sessions);
        if (user == null && !anonymous) throw ApiException.notAuthenticated;
        final isHead = request.method == 'HEAD';
        final handler = methods[isHead ? 'GET' : request.method];
        if (handler == null) {
          throw ApiException.methodNotAllowed(request.method, allowed);
        }
        response = await handler(request, user);
        if (isHead) response = response.change(body: '');
      } on ApiException catch (error) {
        response = error.toResponse();
      }
      return response.change(headers: allow);
    };
  }

  static Response _appendSlash(Request request) {
    final uri = request.requestedUri;
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return Response(
      301,
      headers: {
        'location': '${uri.path}/$query',
        'content-type': 'text/html; charset=utf-8',
      },
    );
  }

  // --- Helpers ---

  Future<Profile> _profileOf(int userId) async {
    final row = (await UsersRepo(database.connection).profile(userId)).orThrow;
    return Profile(row!);
  }

  /// `request.build_absolute_uri(path)`.
  static String _absolute(Request request, String path) {
    final uri = request.requestedUri;
    return '${uri.scheme}://${request.headers['host'] ?? uri.authority}$path';
  }

  static Map<String, Object?> _bookmarkJson(
    Request request,
    BookmarkRow row,
    List<String> tags,
  ) => Bookmark(
    id: row.id,
    url: row.url,
    title: row.title,
    description: row.description,
    notes: row.notes,
    webArchiveSnapshotUrl: row.webArchiveSnapshotUrl.isNotEmpty
        ? row.webArchiveSnapshotUrl
        : (row.url.isEmpty
              ? null
              : webArchiveFallbackUrl(row.url, row.dateAdded)),
    faviconUrl: row.faviconFile.isEmpty
        ? null
        : _absolute(request, '/static/${row.faviconFile}'),
    previewImageUrl: row.previewImageFile.isEmpty
        ? null
        : _absolute(request, '/static/${row.previewImageFile}'),
    isArchived: row.isArchived,
    unread: row.unread,
    shared: row.shared,
    tagNames: [...tags]..sort(),
    dateAdded: row.dateAdded,
    dateModified: row.dateModified,
  ).toJson();

  Future<Map<String, Object?>> _serialize(
    Request request,
    BookmarkRow row,
  ) async {
    final tags = await bookmarks.tagNames([row.id]);
    return _bookmarkJson(request, row, tags[row.id] ?? const []);
  }

  /// The id in the path: 404 "Not found." when it is not a number, and
  /// "No ... matches" when no such row exists.
  static Future<int> _pathId(Request request, String model) async {
    final raw = await request.path<String>('id');
    final id = int.tryParse(raw);
    if (id == null) throw ApiException.notFound;
    if (id < -2147483648 || id > 2147483647) throw ApiException.noMatch(model);
    return id;
  }

  Future<BookmarkRow> _ownedBookmark(Request request, UserRow user) async {
    final id = await _pathId(request, 'Bookmark');
    final row = (await BookmarksRepo(
      database.connection,
    ).owned(id, user.id)).orThrow;
    if (row == null) throw ApiException.noMatch('Bookmark');
    return row;
  }

  // --- Bookmarks ---

  Future<Response> _root(Request request, UserRow? user) async =>
      apiJson(const <String, Object?>{});

  Future<Response> _listActive(Request request, UserRow? user) =>
      _list(request, user!, BookmarkList.active);

  Future<Response> _listArchived(Request request, UserRow? user) =>
      _list(request, user!, BookmarkList.archived);

  Future<Response> _list(
    Request request,
    UserRow user,
    BookmarkList list,
  ) async {
    final query = request.requestedUri.queryParameters;
    final profile = await _profileOf(user.id);
    final search = await BookmarkSearch.fromQuery(
      database.connection,
      query,
      ownerId: user.id,
    );
    final matches = await BookmarkSearchQuery(database.connection)
        .run(list: list, search: search, profile: profile, ownerId: user.id);
    return _page(request, matches);
  }

  /// `GET /api/bookmarks/shared/`: shared bookmarks of users who enabled
  /// sharing; without credentials, only of those who share publicly. An
  /// unknown `user` shows everyone's, as in linkding.
  Future<Response> _listShared(Request request, UserRow? user) async {
    final query = request.requestedUri.queryParameters;
    final search = await BookmarkSearch.fromQuery(database.connection, query);
    final owner = search.user.isEmpty
        ? null
        : (await UsersRepo(database.connection).byUsername(search.user))
              .orThrow;
    final profile = user != null
        ? await _profileOf(user.id)
        : await _guestProfile();
    final matches = await BookmarkSearchQuery(database.connection).run(
      list: BookmarkList.shared,
      search: search,
      profile: profile,
      ownerId: owner?.id,
      publicOnly: user == null,
    );
    return _page(request, matches);
  }

  /// What anonymous visitors search with: the guest profile's preferences
  /// when one is configured.
  Future<Profile?> _guestProfile() async {
    final global = (await SettingsRepo(database.connection).global()).orThrow;
    final guest = global?.guestProfileUserId;
    return guest == null ? null : _profileOf(guest);
  }

  Future<Response> _page(Request request, List<Candidate> matches) async {
    final page = LimitOffset.fromQuery(request.requestedUri.queryParameters);
    final count = matches.length;
    final slice = count == 0 || page.offset > count
        ? const <Candidate>[]
        : matches.skip(page.offset).take(page.limit).toList();
    final url = request.requestedUri.toString();
    return apiJson({
      'count': count,
      'next': page.next(url, count),
      'previous': page.previous(url),
      'results': [for (final c in slice) _bookmarkJson(request, c.row, c.tags)],
    });
  }

  Future<Response> _retrieve(Request request, UserRow? user) async =>
      apiJson(await _serialize(request, await _ownedBookmark(request, user!)));

  /// `GET /api/bookmarks/check/?url=`.
  Future<Response> _check(Request request, UserRow? user) async {
    final query = request.requestedUri.queryParameters;
    final url = query['url'];
    final existing = (await BookmarksRepo(
      database.connection,
    ).existing(user!.id, normalizeUrl(url), url ?? '')).orThrow;
    final page = await metadata.load(
      url,
      ignoreCache: query['ignore_cache'] == 'true',
    );
    final profile = await _profileOf(user.id);
    var tags = const <String>[];
    if (profile.autoTaggingRules.isNotEmpty && url != null) {
      try {
        tags = autoTags(profile.autoTaggingRules, url).toList()..sort();
      } on AutoTaggingError {
        // no automatic tags, as in linkding
      }
    }
    return apiJson({
      'bookmark': existing == null ? null : await _serialize(request, existing),
      'metadata': page.toJson(),
      'auto_tags': tags,
    });
  }

  /// The bookmark fields of a request body, checked in linkding's order.
  /// Absent fields are null.
  ({
    String? url,
    String? title,
    String? description,
    String? notes,
    bool? isArchived,
    bool? unread,
    bool? shared,
    List<String>? tagNames,
    DateTime? dateAdded,
    DateTime? dateModified,
  })
  _bookmarkFields(RequestBody body, {required bool partial}) {
    requireObject(body);
    final errors = FieldErrors();
    T? read<T>(
      String name,
      T Function(Object?) parse, {
      bool required = false,
      bool checkbox = false,
      bool list = false,
      bool blankIsAbsent = false,
    }) {
      final field = fieldOf(
        body,
        name,
        partial: partial,
        checkbox: checkbox,
        list: list,
      );
      if (!field.present) {
        if (required && !partial) {
          errors.errors[name] = ['This field is required.'];
        }
        return null;
      }
      if (blankIsAbsent && body.isForm && field.value == '') return null;
      return errors.check(name, () => parse(field.value));
    }

    final validator = validUrl(disabled: config.disableUrlValidation);
    final url = read(
      'url',
      (v) => text(v, maxLength: 2048, validators: [validator]),
      required: true,
    );
    final title = read(
      'title',
      (v) => text(v, allowBlank: true, maxLength: 512),
    );
    final description = read('description', (v) => text(v, allowBlank: true));
    final notes = read('notes', (v) => text(v, allowBlank: true));
    final isArchived = read('is_archived', boolean, checkbox: true);
    final unread = read('unread', boolean, checkbox: true);
    final shared = read('shared', boolean, checkbox: true);
    final tagNames = read('tag_names', stringList, list: true);
    final dateAdded = read('date_added', dateTime, blankIsAbsent: true);
    final dateModified = read('date_modified', dateTime, blankIsAbsent: true);
    errors.throwIfAny();
    return (
      url: url,
      title: title,
      description: description,
      notes: notes,
      isArchived: isArchived,
      unread: unread,
      shared: shared,
      tagNames: tagNames,
      dateAdded: dateAdded,
      dateModified: dateModified,
    );
  }

  /// `POST /api/bookmarks/`: creates, or updates the bookmark already saved
  /// for the URL. `201` either way, with the URL as `Location`.
  Future<Response> _create(Request request, UserRow? user) async {
    final fields = _bookmarkFields(
      await readRequestBody(request),
      partial: false,
    );
    final profile = await _profileOf(user!.id);
    final saved = await bookmarks.create(
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
      profile,
      scrape:
          config.enableMetadataScraping &&
          !request.requestedUri.queryParameters.containsKey('disable_scraping'),
    );
    return apiJson(
      await _serialize(request, saved),
      status: 201,
      headers: {'location': saved.url},
    );
  }

  /// `PUT` and `PATCH`: fields not sent keep their values either way.
  Future<Response> _update(
    Request request,
    UserRow user, {
    required bool partial,
  }) async {
    final row = await _ownedBookmark(request, user);
    final fields = _bookmarkFields(
      await readRequestBody(request),
      partial: partial,
    );
    final repo = BookmarksRepo(database.connection);
    if (fields.url != null &&
        (await repo.urlTaken(user.id, fields.url!, row.id)).orThrow) {
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
      await _profileOf(user.id),
    );
    return apiJson(await _serialize(request, saved));
  }

  Future<Response> _archive(
    Request request,
    UserRow user,
    bool archived,
  ) async {
    final row = await _ownedBookmark(request, user);
    await bookmarks.setArchived(user.id, [row.id], archived);
    return Response(204);
  }

  Future<Response> _delete(Request request, UserRow? user) async {
    final row = await _ownedBookmark(request, user!);
    await bookmarks.delete(user.id, [row.id]);
    return Response(204);
  }

  // --- Tags ---

  static Map<String, Object?> _tagJson(TagRow row) =>
      Tag(id: row.id, name: row.name, dateAdded: row.dateAdded).toJson();

  Future<Response> _listTags(Request request, UserRow? user) async {
    final page = LimitOffset.fromQuery(request.requestedUri.queryParameters);
    final tags = TagsRepo(database.connection);
    final count = (await tags.count(user!.id)).orThrow;
    final rows = count == 0 || page.offset > count
        ? const <TagRow>[]
        : (await tags.page(user.id, page.limit, page.offset)).orThrow;
    final url = request.requestedUri.toString();
    return apiJson({
      'count': count,
      'next': page.next(url, count),
      'previous': page.previous(url),
      'results': [for (final row in rows) _tagJson(row)],
    });
  }

  /// `POST /api/tags/`: the existing tag when the name is taken in any case.
  Future<Response> _createTag(Request request, UserRow? user) async {
    final body = await readRequestBody(request);
    requireObject(body);
    final errors = FieldErrors();
    final field = fieldOf(body, 'name', partial: false);
    String? name;
    if (!field.present) {
      errors.errors['name'] = ['This field is required.'];
    } else {
      name = errors.check('name', () => text(field.value, maxLength: 64));
    }
    errors.throwIfAny();
    final tag = await getOrCreateTag(database.connection, user!.id, name!);
    return apiJson(_tagJson(tag), status: 201);
  }

  Future<TagRow> _ownedTag(Request request, UserRow user) async {
    final id = await _pathId(request, 'Tag');
    final row = (await TagsRepo(
      database.connection,
    ).owned(id, user.id)).orThrow;
    if (row == null) throw ApiException.noMatch('Tag');
    return row;
  }

  Future<Response> _retrieveTag(Request request, UserRow? user) async =>
      apiJson(_tagJson(await _ownedTag(request, user!)));

  Future<Response> _deleteTag(Request request, UserRow? user) async {
    final tag = await _ownedTag(request, user!);
    (await TagsRepo(database.connection).delete(tag.id, user.id)).orThrow;
    return Response(204);
  }

  // --- Bundles ---

  static Map<String, Object?> _bundleJson(BundleRow row) => Bundle(
    id: row.id,
    name: row.name,
    search: row.search,
    anyTags: row.anyTags,
    allTags: row.allTags,
    excludedTags: row.excludedTags,
    filterUnread: row.filterUnread,
    filterShared: row.filterShared,
    order: row.order,
    dateCreated: row.dateCreated,
    dateModified: row.dateModified,
  ).toJson();

  static const _filterChoices = {'off', 'yes', 'no'};

  ({
    String? name,
    String? search,
    String? anyTags,
    String? allTags,
    String? excludedTags,
    String? filterUnread,
    String? filterShared,
    int? order,
  })
  _bundleFields(RequestBody body, {required bool partial}) {
    requireObject(body);
    final errors = FieldErrors();
    T? read<T>(
      String name,
      T Function(Object?) parse, {
      bool required = false,
    }) {
      final field = fieldOf(body, name, partial: partial);
      if (!field.present) {
        if (required && !partial) {
          errors.errors[name] = ['This field is required.'];
        }
        return null;
      }
      return errors.check(name, () => parse(field.value));
    }

    final result = (
      name: read('name', (v) => text(v, maxLength: 256), required: true),
      search: read('search', (v) => text(v, allowBlank: true, maxLength: 256)),
      anyTags: read(
        'any_tags',
        (v) => text(v, allowBlank: true, maxLength: 1024),
      ),
      allTags: read(
        'all_tags',
        (v) => text(v, allowBlank: true, maxLength: 1024),
      ),
      excludedTags: read(
        'excluded_tags',
        (v) => text(v, allowBlank: true, maxLength: 1024),
      ),
      filterUnread: read('filter_unread', (v) => choice(v, _filterChoices)),
      filterShared: read('filter_shared', (v) => choice(v, _filterChoices)),
      order: read('order', integer),
    );
    errors.throwIfAny();
    return result;
  }

  Future<Response> _listBundles(Request request, UserRow? user) async {
    final page = LimitOffset.fromQuery(request.requestedUri.queryParameters);
    final bundles = BundlesRepo(database.connection);
    final count = (await bundles.count(user!.id)).orThrow;
    final rows = count == 0 || page.offset > count
        ? const <BundleRow>[]
        : (await bundles.page(user.id, page.limit, page.offset)).orThrow;
    final url = request.requestedUri.toString();
    return apiJson({
      'count': count,
      'next': page.next(url, count),
      'previous': page.previous(url),
      'results': [for (final row in rows) _bundleJson(row)],
    });
  }

  /// `POST /api/bundles/`: placed last unless an `order` is given.
  Future<Response> _createBundle(Request request, UserRow? user) async {
    final f = _bundleFields(await readRequestBody(request), partial: false);
    final repo = BundlesRepo(database.connection);
    final order = f.order ?? (await repo.nextOrder(user!.id)).orThrow;
    final row = (await repo.insert(
      f.name!,
      f.search ?? '',
      f.anyTags ?? '',
      f.allTags ?? '',
      f.excludedTags ?? '',
      order,
      DateTime.now().toUtc(),
      user!.id,
      f.filterShared ?? 'off',
      f.filterUnread ?? 'off',
    )).orThrow;
    return apiJson(_bundleJson(row), status: 201);
  }

  Future<BundleRow> _ownedBundle(Request request, UserRow user) async {
    final id = await _pathId(request, 'BookmarkBundle');
    final row = (await BundlesRepo(
      database.connection,
    ).owned(id, user.id)).orThrow;
    if (row == null) throw ApiException.noMatch('BookmarkBundle');
    return row;
  }

  Future<Response> _retrieveBundle(Request request, UserRow? user) async =>
      apiJson(_bundleJson(await _ownedBundle(request, user!)));

  Future<Response> _updateBundle(
    Request request,
    UserRow user, {
    required bool partial,
  }) async {
    final row = await _ownedBundle(request, user);
    final f = _bundleFields(await readRequestBody(request), partial: partial);
    final saved = (await BundlesRepo(database.connection).update(
      row.id,
      f.name ?? row.name,
      f.search ?? row.search,
      f.anyTags ?? row.anyTags,
      f.allTags ?? row.allTags,
      f.excludedTags ?? row.excludedTags,
      f.order ?? row.order,
      DateTime.now().toUtc(),
      f.filterShared ?? row.filterShared,
      f.filterUnread ?? row.filterUnread,
    )).orThrow;
    return apiJson(_bundleJson(saved));
  }

  /// Deletes a bundle and renumbers the rest 0, 1, 2...
  Future<Response> _deleteBundle(Request request, UserRow? user) async {
    final row = await _ownedBundle(request, user!);
    final repo = BundlesRepo(database.connection);
    (await repo.delete(row.id, user.id)).orThrow;
    (await repo.renumber(user.id)).orThrow;
    return Response(204);
  }

  // --- User ---

  Future<Response> _profile(Request request, UserRow? user) async {
    final profile = await _profileOf(user!.id);
    final row = profile.row;
    return apiJson(
      UserProfile(
        theme: row.theme,
        bookmarkDateDisplay: row.bookmarkDateDisplay,
        bookmarkLinkTarget: row.bookmarkLinkTarget,
        webArchiveIntegration: row.webArchiveIntegration,
        tagSearch: row.tagSearch,
        enableSharing: row.enableSharing,
        enablePublicSharing: row.enablePublicSharing,
        enableFavicons: row.enableFavicons,
        displayUrl: row.displayUrl,
        permanentNotes: row.permanentNotes,
        searchPreferences: profile.searchPreferences,
        version: linkdingVersion,
      ).toJson(),
    );
  }
}
