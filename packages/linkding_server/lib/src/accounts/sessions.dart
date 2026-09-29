import 'dart:io';
import 'dart:math';

import 'package:dust_dart/db.dart';
import 'package:dust_server/server.dart';

import '../db/or_throw.dart';
import '../db/rows/rows.dart';
import '../db/repos/sessions_repo.dart';
import '../db/repos/users_repo.dart';

/// linkding's cookie names.
const sessionCookie = 'ld_sessionid';
const csrfCookie = 'ld_csrftoken';

const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
const _csrfAlphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

String _random(int length, String alphabet) {
  final random = Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < length; i++)
      alphabet.codeUnitAt(random.nextInt(alphabet.length)),
  ]);
}

/// A new random API token or feed key, 40 hex digits as linkding makes them.
String newTokenKey() {
  final random = Random.secure();
  return [
    for (var i = 0; i < 20; i++)
      random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

/// The cookies a request sent.
Map<String, String> requestCookies(Request request) {
  final header = request.headers['cookie'];
  if (header == null) return const {};
  final cookies = <String, String>{};
  for (final part in header.split(';')) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    cookies[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
  }
  return cookies;
}

String _cookie(String name, String value, Duration age) {
  final expires = HttpDate.format(DateTime.now().toUtc().add(age));
  return '$name=$value; expires=$expires; Max-Age=${age.inSeconds}; '
      'Path=/; SameSite=Lax';
}

/// Sign-in sessions in the `clone_session` table, and Django-style CSRF
/// protection with a secret in the `ld_csrftoken` cookie.
final class Sessions {
  const Sessions(this.db, {required this.age});

  final Executor db;
  final Duration age;

  /// The active user behind the request's session cookie.
  Future<UserRow?> user(Request request) async {
    final key = requestCookies(request)[sessionCookie];
    if (key == null || key.isEmpty) return null;
    final user = (await UsersRepo(
      db,
    ).bySession(key, DateTime.now().toUtc())).orThrow;
    return user != null && user.isActive ? user : null;
  }

  /// Starts a session for [userId]; returns the `Set-Cookie` value.
  Future<String> start(int userId) async {
    final key = _random(32, _alphabet);
    (await SessionsRepo(
      db,
    ).insertSession(key, userId, DateTime.now().toUtc().add(age))).orThrow;
    return '${_cookie(sessionCookie, key, age)}; HttpOnly';
  }

  /// Django's `update_session_auth_hash` after [userId] changed their
  /// password: the request's session continues under a new key, and every
  /// other session of the user ends. Returns the `Set-Cookie` value.
  Future<String?> keepAfterPasswordChange(Request request, int userId) async {
    final key = requestCookies(request)[sessionCookie];
    if (key == null) return null;
    final renewed = _random(32, _alphabet);
    (await SessionsRepo(
      db,
    ).renewSession(key, renewed, DateTime.now().toUtc().add(age))).orThrow;
    (await SessionsRepo(db).deleteOtherSessions(userId, renewed)).orThrow;
    return '${_cookie(sessionCookie, renewed, age)}; HttpOnly';
  }

  /// Ends the request's session; returns the `Set-Cookie` value clearing it.
  Future<String> end(Request request) async {
    final key = requestCookies(request)[sessionCookie];
    if (key != null) (await SessionsRepo(db).deleteSession(key)).orThrow;
    return '$sessionCookie=""; expires=Thu, 01 Jan 1970 00:00:00 GMT; '
        'Max-Age=0; Path=/; SameSite=Lax';
  }

  /// The CSRF secret the request carries, and the cookie to set when it
  /// carried none.
  static ({String token, String? setCookie}) csrfToken(Request request) {
    final existing = requestCookies(request)[csrfCookie];
    if (existing != null && existing.length == 32) {
      return (token: existing, setCookie: null);
    }
    final token = _random(32, _csrfAlphabet);
    return (
      token: token,
      setCookie: _cookie(csrfCookie, token, const Duration(days: 364)),
    );
  }

  /// Django's CSRF check for an unsafe request: the secret from the cookie
  /// must match the one in [submitted] (a form field or `X-CSRFToken`),
  /// plain or masked, and a browser's `Origin` must be this host. Returns
  /// the reason for failing, or null.
  static String? csrfFailure(Request request, String? submitted) {
    final origin = request.headers['origin'];
    if (origin != null) {
      final uri = request.requestedUri;
      final own = '${uri.scheme}://${request.headers['host'] ?? uri.authority}';
      if (origin != own) {
        return 'Origin checking failed - $origin does not match any trusted '
            'origins.';
      }
    }
    final secret = requestCookies(request)[csrfCookie];
    if (secret == null || secret.length != 32) return 'CSRF cookie not set.';
    final token = submitted ?? request.headers['x-csrftoken'];
    if (token == null || token.isEmpty) return 'CSRF token missing.';
    final unmasked = switch (token.length) {
      32 => token,
      64 => _unmask(token),
      _ => null,
    };
    if (unmasked == null) return 'CSRF token has incorrect length.';
    return unmasked == secret ? null : 'CSRF token incorrect.';
  }

  /// Undoes Django's per-page masking of the CSRF secret.
  static String? _unmask(String token) {
    final mask = token.substring(0, 32);
    final cipher = token.substring(32);
    final out = StringBuffer();
    for (var i = 0; i < 32; i++) {
      final m = _csrfAlphabet.indexOf(mask[i]);
      final c = _csrfAlphabet.indexOf(cipher[i]);
      if (m < 0 || c < 0) return null;
      out.write(_csrfAlphabet[(c - m) % _csrfAlphabet.length]);
    }
    return out.toString();
  }
}
