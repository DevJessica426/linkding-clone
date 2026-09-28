import 'dart:io';
import 'dart:math';

import 'package:dust_server/server.dart';

/// The cookie holding a visitor's CSRF secret.
const csrfCookie = 'ld_csrftoken';

const _alphabet =
    'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

String _random(int length) {
  final random = Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < length; i++)
      _alphabet.codeUnitAt(random.nextInt(_alphabet.length)),
  ]);
}

/// A visitor's CSRF secret: the one their cookie carries, or a new one the
/// response has to set.
final class CsrfSecret {
  CsrfSecret._(this.value, {required this.isNew});

  /// The request's secret, or a fresh one when it carries none.
  factory CsrfSecret.of(Request request) {
    final existing = CookieJar.of(request).values[csrfCookie];
    if (existing != null && existing.length == 32) {
      return CsrfSecret._(existing, isNew: false);
    }
    return CsrfSecret._(_random(32), isNew: true);
  }

  /// A new secret, as Django's `rotate_token` makes one on signing in.
  factory CsrfSecret.rotated() => CsrfSecret._(_random(32), isNew: true);

  final String value;
  final bool isNew;

  /// Whether a page used the secret. Only then does a new one's cookie get
  /// set, as Django sets it after `get_token`.
  var used = false;

  /// The `Set-Cookie` value for a new secret, kept for a year as Django
  /// keeps it.
  String? get setCookie {
    if (!isNew) return null;
    const age = Duration(days: 364);
    final expires = HttpDate.format(DateTime.now().toUtc().add(age));
    return '$csrfCookie=$value; expires=$expires; Max-Age=${age.inSeconds}; '
        'Path=/; SameSite=Lax';
  }

  /// Django's per-page masking, so the token in a page differs from the
  /// cookie while still proving it.
  String masked() {
    used = true;
    final mask = _random(32);
    final out = StringBuffer(mask);
    for (var i = 0; i < 32; i++) {
      final s = _alphabet.indexOf(value[i]);
      final m = _alphabet.indexOf(mask[i]);
      out.write(_alphabet[(s + m) % _alphabet.length]);
    }
    return out.toString();
  }
}

/// Django's CSRF check for an unsafe request: the cookie's secret must
/// match [submitted] (the form field, else `X-CSRFToken`), plain or masked,
/// and a browser's `Origin` must be this host. The reason for failing, or
/// null.
String? csrfFailure(Request request, String? submitted) {
  final origin = request.headers['origin'];
  if (origin != null) {
    final uri = request.requestedUri;
    final own = '${uri.scheme}://${request.headers['host'] ?? uri.authority}';
    if (origin != own) {
      return 'Origin checking failed - $origin does not match any trusted '
          'origins.';
    }
  }
  final secret = CookieJar.of(request).values[csrfCookie];
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

String? _unmask(String token) {
  final out = StringBuffer();
  for (var i = 0; i < 32; i++) {
    final m = _alphabet.indexOf(token[i]);
    final c = _alphabet.indexOf(token[32 + i]);
    if (m < 0 || c < 0) return null;
    out.write(_alphabet[(c - m) % _alphabet.length]);
  }
  return out.toString();
}
