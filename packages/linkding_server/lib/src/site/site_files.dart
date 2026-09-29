import 'package:dust_server/server.dart';

import '../pages/html.dart';
import '../pages/visitor.dart';

/// `/opensearch.xml`: linkding's search, for the browser's address bar.
Future<Response> opensearch(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final base = e(visitor.baseUrl);
  return Response.ok(
    '<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/" '
    'xmlns:moz="http://www.mozilla.org/2006/browser/search/">\n'
    '    <ShortName>Linkding</ShortName>\n'
    '    <Description>Linkding</Description>\n'
    '    <InputEncoding>UTF-8</InputEncoding>\n'
    '    <Image width="16" height="16" type="image/x-icon">'
    '$base/static/favicon.ico</Image>\n'
    '    <Url type="text/html" template="$base/bookmarks?client=opensearch'
    '&amp;q={searchTerms}"/>\n'
    '</OpenSearchDescription>\n',
    headers: {'content-type': 'application/opensearchdescription+xml'},
  );
}

/// `/custom_css`: the visitor's custom CSS, cached for 30 days (the pages
/// link it with the CSS's hash).
Future<Response> customCss(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  return Response.ok(
    visitor.profile.row.customCss,
    headers: {
      'content-type': 'text/css',
      'cache-control': 'public, max-age=2592000',
    },
  );
}
