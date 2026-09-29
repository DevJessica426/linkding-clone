import 'dart:convert';

import 'package:dust_server/server.dart';

/// A JSON response as linkding sends it: compact UTF-8.
Response apiJson(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: body == null ? null : jsonEncode(body),
  headers: {'content-type': 'application/json', ...headers},
);

/// A failed API request, answered with its status and JSON body.
final class ApiException implements Exception, IntoResponse {
  const ApiException(this.status, this.body, {this.headers = const {}});

  ApiException.detail(
    int status,
    String detail, {
    Map<String, String> headers = const {},
  }) : this(status, {'detail': detail}, headers: headers);

  static const _challenge = {'www-authenticate': 'Token'};

  static final notAuthenticated = ApiException.detail(
    401,
    'Authentication credentials were not provided.',
    headers: _challenge,
  );

  static ApiException authenticationFailed(String detail) =>
      ApiException.detail(401, detail, headers: _challenge);

  /// 404 for an id that exists nowhere, naming the model as Django does.
  static ApiException noMatch(String model) =>
      ApiException.detail(404, 'No $model matches the given query.');

  /// 404 for an id that is not a number at all.
  static final notFound = ApiException.detail(404, 'Not found.');

  static ApiException methodNotAllowed(String method, List<String> allowed) =>
      ApiException.detail(
        405,
        'Method "$method" not allowed.',
        headers: {'allow': allowed.join(', ')},
      );

  /// 400 with messages by field name.
  static ApiException invalid(Map<String, Object> errors) =>
      ApiException(400, errors);

  final int status;
  final Object body;
  final Map<String, String> headers;

  @override
  Response intoResponse() => apiJson(body, status: status, headers: headers);
}
