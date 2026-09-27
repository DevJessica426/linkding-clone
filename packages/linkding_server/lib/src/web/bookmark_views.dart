import 'dart:async';
import 'dart:convert';

import 'package:dust_dart/db.dart';
import 'package:dust_server/server.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../auth/sessions.dart';
import '../compat/pyurl.dart';
import '../core/profile.dart';
import '../db/assets_repo.dart';
import '../db/bookmarks_repo.dart';
import '../db/bundles_repo.dart';
import '../db/rows.dart';
import '../db/tags_repo.dart';
import '../db/users_repo.dart';
import '../services/errors.dart';
import '../services/search.dart';
import 'bookmark_list.dart';
import 'context.dart';
import 'format.dart';
import 'forms.dart';
import 'layout.dart';
import 'query_params.dart';

/// linkding's `views/bookmarks.py`: the three lists and what their forms
/// post.
final class BookmarkViews {
  BookmarkViews(this.web);

  final Web web;

  Executor get _db => web.database.connection;

  Future<Response> index(Request request) => _list(request, ListKind.active);
  Future<Response> archived(Request request) =>
      _list(request, ListKind.archived);
  Future<Response> shared(Request request) => _list(request, ListKind.shared);

  Future<Response> indexAction(Request request) =>
      _action(request, ListKind.active);
  Future<Response> archivedAction(Request request) =>
      _action(request, ListKind.archived);
  Future<Response> sharedAction(Request request) =>
      _action(request, ListKind.shared);

  Future<Response> _list(Request request, ListKind kind) async {
    final c = await web.context(request);
    FormData? form;
    if (request.method == 'POST') {
      form = await readFormData(request);
      final failure = _csrf(request, form);
      if (failure != null) return csrfFailurePage(c, failure);
    }
    if (kind != ListKind.shared && !c.isAuthenticated) {
      return redirectToLogin(c);
    }
    if (form != null) return _searchAction(c, form);

    final page = await _page(
      c,
      kind,
      QueryParams.parse(request.requestedUri.query),
    );
    return c.html(
      layout(
        c,
        title: page.details != null
            ? 'Bookmark details - Linkding'
            : '${kind.title} - Linkding',
        content: bookmarkPageContent(c, page),
        overlays: detailsModal(c, page),
        rssFeedUrl: kind == ListKind.shared ? '/feeds/shared' : null,
      ),
    );
  }

  /// Everything one list page shows, as `index`, `archived` and `shared`
  /// gather it.
  Future<ListPage> _page(
    PageContext c,
    ListKind kind,
    QueryParams query,
  ) async {
    final profile = c.profile;
    final userId = c.user?.id;
    final publicOnly = !c.isAuthenticated;
    final search = await BookmarkSearch.fromQuery(
      _db,
      query.last,
      ownerId: userId,
      preferences: profile.searchPreferences,
    );

    var ownerId = userId;
    if (kind == ListKind.shared) {
      ownerId = search.user.isEmpty
          ? null
          : (await UsersRepo(_db).byUsername(search.user)).orThrow?.id;
    }
    final candidates = await _search(
      kind,
      search,
      profile,
      ownerId,
      publicOnly,
    );
    final page = Page.of(candidates, profile.row.itemsPerPage, query['page']);

    final ownerIds = {for (final item in page.items) item.row.ownerId};
    final owners = {
      for (final u in (await UsersRepo(_db).names([...ownerIds])).orThrow)
        u.id: u.username,
    };

    final tagNames = extractTagNamesFromQuery(
      search.q,
      laxTags: profile.laxTags,
    );
    final selectedTags = tagNames.isEmpty
        ? const <TagRow>[]
        : kind == ListKind.shared
        ? (await TagsRepo(
            _db,
          ).sharedNamed(ownerId, publicOnly, tagNames)).orThrow
        : (await TagsRepo(_db).withNames(userId!, tagNames)).orThrow;
    final tagCloud = TagCloud.of(profile.row.tagGrouping, [
      for (final candidate in candidates) ...candidate.tagRows,
    ], selectedTags);

    List<BundleRow>? bundles;
    List<String>? users;
    if (kind == ListKind.shared) {
      final everyone = ownerId == null
          ? candidates
          : await _search(kind, search, profile, null, publicOnly);
      final names = (await UsersRepo(_db).names([
        ...{for (final c in everyone) c.row.ownerId},
      ])).orThrow;
      users = [for (final u in names) u.username]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    } else {
      bundles = (await BundlesRepo(_db).all(userId!)).orThrow;
    }

    return ListPage(
      kind: kind,
      links: ListLinks(kind, query, profile),
      query: query,
      search: search,
      page: page,
      owners: owners,
      tagCloud: tagCloud,
      bundles: bundles,
      selectedBundleId: int.tryParse(query['bundle'] ?? ''),
      users: users,
      details: await _details(c, query['details']),
    );
  }

  Future<List<Candidate>> _search(
    ListKind kind,
    BookmarkSearch search,
    Profile profile,
    int? ownerId,
    bool publicOnly,
  ) => BookmarkSearchQuery(_db).run(
    list: kind.list,
    search: search,
    profile: profile,
    ownerId: ownerId,
    publicOnly: publicOnly,
  );

  /// `get_details_context`: the bookmark in `?details=`, when the visitor
  /// may see it.
  Future<Details?> _details(PageContext c, String? id) async {
    final bookmarkId = int.tryParse(id ?? '');
    if (bookmarkId == null) return null;
    final bookmark = await _readable(c, bookmarkId);
    if (bookmark == null) return null;
    final tags = (await BookmarksRepo(_db).tagNames([bookmark.id])).orThrow;
    return Details(
      bookmark: bookmark,
      tags: [for (final t in tags) t.name]..sort(),
      assets: (await BookmarksRepo(_db).assets(bookmark.id)).orThrow,
      isEditable: bookmark.ownerId == c.user?.id,
      uploadsEnabled: !web.config.disableAssetUpload,
    );
  }

  /// `access.bookmark_read`: the owner's, or shared by an owner who shares
  /// with users (for signed-in visitors) or publicly.
  Future<BookmarkRow?> _readable(PageContext c, int id) async {
    final bookmark = (await BookmarksRepo(_db).byId(id)).orThrow;
    if (bookmark == null) return null;
    if (bookmark.ownerId == c.user?.id) return bookmark;
    if (!bookmark.shared) return null;
    final owner = (await UsersRepo(_db).profile(bookmark.ownerId)).orThrow;
    if (owner == null) return null;
    final visible =
        (c.isAuthenticated && owner.enableSharing) || owner.enablePublicSharing;
    return visible ? bookmark : null;
  }

  /// `search_action`: applies the search preferences form, saving them as
  /// the defaults when asked, and goes back to the list with the search in
  /// the query string.
  Future<Response> _searchAction(PageContext c, FormData form) async {
    final post = {
      for (final MapEntry(:key, :value) in form.fields.entries) key: value.last,
    };
    var preferences = c.profile.searchPreferences;
    if (form.has('save')) {
      final user = c.user;
      if (user == null) {
        return Response(
          403,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      final saved = await BookmarkSearch.fromQuery(_db, post, ownerId: user.id);
      preferences = {
        'sort': saved.sort,
        'shared': saved.shared,
        'unread': saved.unread,
      };
      (await UsersRepo(
        _db,
      ).setSearchPreferences(user.id, jsonEncode(preferences))).orThrow;
    }
    final search = await BookmarkSearch.fromQuery(
      _db,
      post,
      ownerId: c.user?.id,
      preferences: preferences,
    );
    final query = urlencode(modifiedSearchParams(search));
    return c.redirect(query.isEmpty ? c.path : '${c.path}?$query');
  }

  /// `index_action`, `archived_action` and `shared_action`.
  Future<Response> _action(Request request, ListKind kind) async {
    final c = await web.context(request);
    if (request.method != 'POST') {
      if (!c.isAuthenticated) return redirectToLogin(c);
      return c.redirect(_withQuery(kind.indexUrl, c));
    }
    final form = await readFormData(request);
    final failure = _csrf(request, form);
    if (failure != null) return csrfFailurePage(c, failure);
    final user = c.user;
    if (user == null) return redirectToLogin(c);
    if (kind == ListKind.shared && form.has('bulk_execute')) {
      return Response(
        400,
        body: 'View does not support bulk actions',
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }
    final response = await _handle(c, kind, user.id, form);
    return response ?? c.redirect(_withQuery(kind.indexUrl, c));
  }

  /// `handle_action`: one button of the list or the details view, or a
  /// bulk action. Returns a response only when the action fails.
  Future<Response?> _handle(
    PageContext c,
    ListKind kind,
    int userId,
    FormData form,
  ) async {
    final bookmarks = web.bookmarks;

    Future<Response?> owned(
      String key,
      Future<void> Function(BookmarkRow bookmark) action,
    ) async {
      final id = int.tryParse(form[key] ?? '');
      final bookmark = id == null
          ? null
          : (await BookmarksRepo(_db).owned(id, userId)).orThrow;
      if (bookmark == null) return notFoundPage();
      await action(bookmark);
      return null;
    }

    if (form.has('archive')) {
      return owned(
        'archive',
        (b) => bookmarks.setArchived(userId, [b.id], true),
      );
    }
    if (form.has('unarchive')) {
      return owned(
        'unarchive',
        (b) => bookmarks.setArchived(userId, [b.id], false),
      );
    }
    if (form.has('remove')) {
      return owned('remove', (b) => bookmarks.delete(userId, [b.id]));
    }
    if (form.has('mark_as_read')) {
      return owned(
        'mark_as_read',
        (b) async => (await BookmarksRepo(_db).markRead(b.id, userId)).orThrow,
      );
    }
    if (form.has('unshare')) {
      return owned(
        'unshare',
        (b) async => (await BookmarksRepo(
          _db,
        ).setState(b.id, userId, b.isArchived, b.unread, false)).orThrow,
      );
    }
    if (form.has('create_html_snapshot')) {
      // Snapshots need linkding's single-file tooling; like linkding without
      // LD_ENABLE_SNAPSHOTS, the request is accepted and nothing happens.
      return owned('create_html_snapshot', (_) async {});
    }
    if (form.has('upload_asset')) {
      if (web.config.disableAssetUpload) {
        return Response(
          403,
          body: 'Asset upload is disabled',
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      Response? missing;
      final notFound = await owned('upload_asset', (b) async {
        final file = form.files['upload_asset_file'];
        if (file == null) {
          missing = Response(
            400,
            body: 'No file provided',
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
          return;
        }
        await web.assets.upload(b, file.name, file.contentType, file.bytes);
      });
      return notFound ?? missing;
    }
    if (form.has('remove_asset')) {
      final id = int.tryParse(form['remove_asset'] ?? '');
      final asset = id == null
          ? null
          : (await AssetsRepo(_db).owned(id, userId)).orThrow;
      if (asset == null) return notFoundPage();
      await web.assets.remove(asset);
      return null;
    }
    if (form.has('update_state')) {
      return owned(
        'update_state',
        (b) async => (await BookmarksRepo(_db).setState(
          b.id,
          userId,
          form['is_archived'] == 'on',
          form['unread'] == 'on',
          form['shared'] == 'on',
        )).orThrow,
      );
    }
    if (form.has('bulk_execute')) {
      final ids = form['bulk_select_across'] == 'on'
          ? await _allMatching(c, kind)
          : [
              for (final id in form.list('bookmark_id'))
                ?int.tryParse(id.trim()),
            ];
      final tagString = (form['bulk_tag_string'] ?? '').replaceAll(' ', ',');
      switch (form['bulk_action']) {
        case 'bulk_archive':
          await bookmarks.setArchived(userId, ids, true);
        case 'bulk_unarchive':
          await bookmarks.setArchived(userId, ids, false);
        case 'bulk_delete':
          await bookmarks.delete(userId, ids);
        case 'bulk_tag':
          await bookmarks.tag(userId, ids, tagString);
        case 'bulk_untag':
          await bookmarks.untag(userId, ids, tagString);
        case 'bulk_read':
          await bookmarks.setUnread(userId, ids, false);
        case 'bulk_unread':
          await bookmarks.setUnread(userId, ids, true);
        case 'bulk_share':
          await bookmarks.setShared(userId, ids, true);
        case 'bulk_unshare':
          await bookmarks.setShared(userId, ids, false);
        case 'bulk_refresh':
          // A background task in linkding: the page does not wait for it.
          unawaited(
            bookmarks.refreshMetadata(userId, ids).catchError((Object _) {}),
          );
      }
    }
    return null;
  }

  /// Every bookmark the list's current search matches, for "select all".
  Future<List<int>> _allMatching(PageContext c, ListKind kind) async {
    final query = QueryParams.parse(c.request.requestedUri.query);
    final search = await BookmarkSearch.fromQuery(
      _db,
      query.last,
      ownerId: c.user!.id,
      preferences: c.profile.searchPreferences,
    );
    final matches = await _search(kind, search, c.profile, c.user!.id, false);
    return [for (final m in matches) m.row.id];
  }

  static String? _csrf(Request request, FormData form) =>
      Sessions.csrfFailure(request, form['csrfmiddlewaretoken']);

  /// `redirect_with_query`: [url] with the request's query parameters, the
  /// last value of each.
  static String _withQuery(String url, PageContext c) {
    final query = urlencode([
      for (final MapEntry(:key, :value) in QueryParams.parse(
        c.request.requestedUri.query,
      ).last.entries)
        (key, value),
    ]);
    return query.isEmpty ? url : '$url?$query';
  }
}
