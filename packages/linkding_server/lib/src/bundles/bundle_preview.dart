import 'package:dust_server/server.dart';

import '../bookmarks/bookmarks.dart';
import '../db/database.dart';
import '../db/rows/rows.dart';
import '../pages/support/paginator.dart';
import '../pages/support/query_params.dart';
import '../pages/session/visitor.dart';
import '../search/search.dart';
import 'bundle_fields.dart';

/// `/bundles/preview`: the preview frame for the fields in the query.
Future<Response> previewBundle(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final fields = BundleFields.fromData(visitor.query, null);
  return htmlResponse(
    await renderPreview(request, fields.toBundle(visitor.signedIn.id)),
  );
}

/// `bundles/preview.html`: the active bookmarks [bundle] matches, as a list
/// without actions.
Future<String> renderPreview(Request request, BundleRow bundle) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final engine = await request.state<TemplateEngine>();
  final db = (await request.state<LinkdingDatabase>()).connection;
  final user = visitor.signedIn;
  final query = QueryParams.parse(request.requestedUri.query);
  final search = BookmarkSearch(bundle: bundle);
  final candidates = await searchList(
    db,
    ListKind.active,
    search,
    visitor.profile,
    ownerId: user.id,
  );
  if (candidates.isEmpty) {
    return engine.render('bundles/preview', const {'hasMatches': false});
  }
  final page = ListPage(
    kind: ListKind.active,
    links: ListLinks(ListKind.active, query, visitor.profile),
    query: query,
    search: search,
    page: Page.of(candidates, visitor.profile.row.itemsPerPage, query['page']),
    owners: {user.id: user.username},
    tagCloud: TagCloud(const [], const []),
    bundles: null,
    selectedBundleId: null,
    users: null,
    details: null,
    isPreview: true,
    paginationFrame: 'preview',
  );
  return engine.render('bundles/preview', {
    'hasMatches': true,
    'count': candidates.length,
    'list': renderList(engine, visitor, page),
  });
}
