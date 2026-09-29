import 'package:dust_server/server.dart';

import '../../compat/form_data.dart';
import '../../pages/support/query.dart';
import '../../pages/support/turbo.dart';
import '../../pages/session/visitor.dart';
import 'action_steps.dart';
import '../details/details_values.dart';
import 'list_kind.dart';
import 'list_loader.dart';
import 'list_values.dart';

/// `/bookmarks/action`.
Future<Response> activeAction(Request request) =>
    _action(request, ListKind.active);

/// `/bookmarks/archived/action`.
Future<Response> archivedAction(Request request) =>
    _action(request, ListKind.archived);

/// `/bookmarks/shared/action`.
Future<Response> sharedAction(Request request) =>
    _action(request, ListKind.shared);

/// linkding's `index_action`, `archived_action` and `shared_action`: one
/// button of the list or the details modal, or a bulk action, then the
/// updated list as Turbo Streams or back to the list.
Future<Response> _action(Request request, ListKind kind) async {
  if (request.method != 'POST') {
    return Redirect.found(withQuery(kind.indexUrl, request)).intoResponse();
  }
  final form = await request.extract(const PostedForm());
  final user = (await request.extract(const Extension<Visitor>())).signedIn;
  if (kind == ListKind.shared && form.has('bulk_execute')) {
    return Response(
      400,
      body: 'View does not support bulk actions',
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }
  final failure = await applyAction(request, kind, user.id, form);
  if (failure != null) return failure;
  final accept = request.headers['accept'] ?? '';
  if (accept.contains(turboStreamType) && form['disable_turbo'] != 'true') {
    return _listUpdate(request, kind);
  }
  return Redirect.found(withQuery(kind.indexUrl, request)).intoResponse();
}

/// linkding's `render_bookmarks_update`: the list, the tag cloud and the
/// details modal as Turbo Stream updates, for the page to swap in without
/// reloading.
Future<Response> _listUpdate(Request request, ListKind kind) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final engine = await request.state<TemplateEngine>();
  final page = await loadListPage(request, kind);
  return turboStream([
    turboUpdate('bookmark-list-container', renderList(engine, visitor, page)),
    turboUpdate('tag-cloud-container', renderTagCloud(engine, page)),
    turboReplace(
      'details-modal',
      renderDetails(engine, visitor, page),
      method: 'morph',
    ),
  ]);
}
