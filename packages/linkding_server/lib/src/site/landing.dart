import 'package:dust_server/server.dart';

import '../pages/query.dart';
import '../pages/visitor.dart';

/// `/`: to the bookmarks, or for visitors to the shared bookmarks when that
/// is the landing page, keeping the query as linkding's
/// `redirect_with_query` does.
Future<Response> root(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final shared =
      !visitor.isAuthenticated &&
      visitor.settings.landingPage == 'shared_bookmarks';
  return Redirect.found(
    withQuery(shared ? '/bookmarks/shared' : '/bookmarks', request),
  ).intoResponse();
}
