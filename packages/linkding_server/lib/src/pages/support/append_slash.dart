import 'package:dust_server/server.dart';

/// Django's `APPEND_SLASH`: a path that only exists with a trailing slash
/// is redirected there, permanently, with its query.
Response appendSlash(Request request) {
  final uri = request.requestedUri;
  final target = uri.hasQuery ? '${uri.path}/?${uri.query}' : '${uri.path}/';
  return Redirect.movedPermanently(target).intoResponse();
}
