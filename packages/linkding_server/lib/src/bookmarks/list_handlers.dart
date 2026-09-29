import 'dart:convert';

import 'package:dust_server/server.dart';

import '../compat/form_data.dart';
import '../compat/pyurl.dart';
import '../db/database.dart';
import '../db/users_repo.dart';
import '../pages/render.dart';
import '../pages/visitor.dart';
import '../services/errors.dart';
import '../services/search.dart';
import 'details_values.dart';
import 'list_kind.dart';
import 'list_loader.dart';
import 'list_values.dart';
import 'page_values.dart';
import 'search_params.dart';

/// `/bookmarks`: the visitor's bookmarks.
Future<Response> activeList(Request request) => _list(request, ListKind.active);

/// `/bookmarks/archived`.
Future<Response> archivedList(Request request) =>
    _list(request, ListKind.archived);

/// `/bookmarks/shared`: everyone's shared bookmarks.
Future<Response> sharedList(Request request) => _list(request, ListKind.shared);

/// A list page, or only its details modal for the Turbo frame that opens
/// it. A `POST` is the search preferences form.
Future<Response> _list(Request request, ListKind kind) async {
  if (request.method == 'POST') return _searchPreferences(request);
  final visitor = await request.extract(const Extension<Visitor>());
  final engine = await request.state<TemplateEngine>();
  final page = await loadListPage(request, kind);
  final title = page.details != null
      ? 'Bookmark details - Linkding'
      : '${kind.title} - Linkding';
  final rssFeedUrl = kind == ListKind.shared ? '/feeds/shared' : null;
  final details = renderDetails(engine, visitor, page);
  if (request.headers['turbo-frame'] == 'details-modal') {
    return renderTopFrame(
      engine,
      visitor,
      title: title,
      frame: details,
      rssFeedUrl: rssFeedUrl,
    );
  }
  return renderPage(
    engine,
    visitor,
    title: title,
    template: 'bookmarks/page',
    values: pageValues(
      visitor,
      page,
      list: renderList(engine, visitor, page),
      tagCloud: renderTagCloud(engine, page),
    ),
    overlays: details,
    rssFeedUrl: rssFeedUrl,
  );
}

/// linkding's `search_action`: applies the search preferences, saving them
/// as the defaults when asked, and goes back to the list with the search
/// in the query string.
Future<Response> _searchPreferences(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final db = (await request.state<LinkdingDatabase>()).connection;
  final form = await request.extract(const PostedForm());
  final post = {
    for (final MapEntry(:key, :value) in form.fields.entries) key: value.last,
  };
  var preferences = visitor.profile.searchPreferences;
  if (form.has('save')) {
    final user = visitor.user;
    if (user == null) {
      return Response(
        403,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }
    final saved = await BookmarkSearch.fromQuery(db, post, ownerId: user.id);
    preferences = {
      'sort': saved.sort,
      'shared': saved.shared,
      'unread': saved.unread,
    };
    (await UsersRepo(
      db,
    ).setSearchPreferences(user.id, jsonEncode(preferences))).orThrow;
  }
  final search = await BookmarkSearch.fromQuery(
    db,
    post,
    ownerId: visitor.user?.id,
    preferences: preferences,
  );
  final query = urlencode(modifiedSearchParams(search));
  return Redirect.found(query.isEmpty ? visitor.path : '${visitor.path}?$query')
      .intoResponse();
}
