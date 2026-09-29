import 'package:dust_server/server.dart';

import '../auth/sessions.dart';
import '../db/database.dart';
import '../db/rows.dart';
import 'authentication.dart';
import 'errors.dart';

/// One method's handler of an API route.
typedef ApiHandler = Future<Response> Function(Request request);

/// Who called the API: a user, or nobody on the public shared list.
final class ApiCaller {
  const ApiCaller(this.user);

  final UserRow? user;
}

/// The signed-in caller of an endpoint behind [apiView], which lets no
/// one else through.
final class ApiUser implements FromRequestParts<UserRow> {
  const ApiUser();

  @override
  Future<Result<UserRow, Rejection>> extract(Request request) async {
    switch (await const Extension<ApiCaller>().extract(request)) {
      case Ok(value: ApiCaller(:final user?)):
        return Ok(user);
      case _:
        return const Err(Rejection.unauthorized('sign in first'));
    }
  }
}

/// A DRF `APIView` over [methods]: authenticates the caller (only
/// [anonymous] views take none), answers a method it lacks with 405, turns
/// an [ApiException] into its response, and names the view's methods in
/// `Allow` on every answer, in DRF's order.
Endpoint<Response> apiView(
  Map<String, ApiHandler> methods, {
  bool anonymous = false,
}) {
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
      final user = await apiUser(
        request,
        (await request.state<LinkdingDatabase>()).connection,
        await request.state<Sessions>(),
      );
      if (user == null && !anonymous) throw ApiException.notAuthenticated;
      final isHead = request.method == 'HEAD';
      final handler = methods[isHead ? 'GET' : request.method];
      if (handler == null) {
        throw ApiException.methodNotAllowed(request.method, allowed);
      }
      response = await handler(
        request.change(
          context: {extensionKeyFor<ApiCaller>(): ApiCaller(user)},
        ),
      );
      if (isHead) response = response.change(body: '');
    } on ApiException catch (error) {
      response = error.intoResponse();
    }
    return response.change(headers: allow);
  };
}

/// Django's `APPEND_SLASH`: the same address with a slash, for a route
/// asked for without one.
Response appendSlash(Request request) {
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
