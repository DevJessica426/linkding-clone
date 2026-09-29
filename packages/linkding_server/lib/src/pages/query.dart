import 'package:dust_server/server.dart';

import '../compat/pyurl.dart';
import 'query_params.dart';

/// linkding's `redirect_with_query`: [url] with the request's query,
/// re-encoded, with the last value of a repeated name.
String withQuery(String url, Request request) {
  final params = QueryParams.parse(request.requestedUri.query).last;
  final encoded = urlencode([
    for (final MapEntry(:key, :value) in params.entries) (key, value),
  ]);
  return encoded.isEmpty ? url : '$url?$encoded';
}
