import 'package:dust_server/server.dart';

import '../compat/pyurl.dart';
import '../pages/visitor.dart';
import '../web/query_params.dart';

/// `/`: to the bookmarks, or for visitors to the shared bookmarks when that
/// is the landing page. The query is kept as linkding's
/// `redirect_with_query` keeps it: re-encoded, with the last value of a
/// repeated name.
Future<Response> root(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final params = QueryParams.parse(request.requestedUri.query).last;
  final encoded = urlencode([
    for (final MapEntry(:key, :value) in params.entries) (key, value),
  ]);
  final query = encoded.isEmpty ? '' : '?$encoded';
  final shared =
      !visitor.isAuthenticated &&
      visitor.settings.landingPage == 'shared_bookmarks';
  return Redirect.found(shared ? '/bookmarks/shared$query' : '/bookmarks$query')
      .intoResponse();
}
