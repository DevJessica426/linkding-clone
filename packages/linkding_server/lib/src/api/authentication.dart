import 'dart:convert';

import 'package:dust_dart/db.dart';
import 'package:dust_server/server.dart';

import '../auth/sessions.dart';
import '../db/rows.dart';
import '../db/users_repo.dart';
import '../services/errors.dart';
import 'errors.dart';

const _safeMethods = {'GET', 'HEAD', 'OPTIONS', 'TRACE'};

/// Who is calling the API, the way linkding decides it: an `Authorization`
/// header with `Token` or `Bearer` first, then the browser session (with a
/// CSRF check on anything but a read). Null when neither applies; wrong
/// credentials throw.
Future<UserRow?> apiUser(
  Request request,
  Executor db,
  Sessions sessions,
) async {
  final header = request.headers['authorization'];
  final parts = header == null
      ? const <String>[]
      : header.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isNotEmpty &&
      const {'token', 'bearer'}.contains(parts.first.toLowerCase())) {
    if (parts.length == 1) {
      throw ApiException.authenticationFailed(
        'Invalid token header. No credentials provided.',
      );
    }
    if (parts.length > 2) {
      throw ApiException.authenticationFailed(
        'Invalid token header. Token string should not contain spaces.',
      );
    }
    try {
      utf8.encode(parts[1]);
    } on Object {
      throw ApiException.authenticationFailed(
        'Invalid token header. Token string should not contain invalid '
        'characters.',
      );
    }
    final user = (await UsersRepo(db).byApiToken(parts[1])).orThrow;
    if (user == null) throw ApiException.authenticationFailed('Invalid token.');
    if (!user.isActive) {
      throw ApiException.authenticationFailed('User inactive or deleted.');
    }
    return user;
  }

  final user = await sessions.user(request);
  if (user == null) return null;
  if (!_safeMethods.contains(request.method)) {
    final failure = Sessions.csrfFailure(request, null);
    if (failure != null) {
      throw ApiException.detail(403, 'CSRF Failed: $failure');
    }
  }
  return user;
}
