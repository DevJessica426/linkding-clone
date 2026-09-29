import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:webcrypto/webcrypto.dart';

/// Django's default password hasher, `pbkdf2_sha256`.
///
/// Hashes are stored as `pbkdf2_sha256$<iterations>$<salt>$<base64 hash>`,
/// exactly as linkding stores them, so users of an existing linkding
/// database sign in with their existing passwords, and linkding accepts
/// passwords set here.
///
/// Django's 1,200,000 rounds are slow on purpose. `package:webcrypto` runs
/// them in BoringSSL in about 0.2 s; the pure-Dart packages take 4 to 5 s.
/// The work runs in a background isolate so other requests are not held up.
final class PasswordHasher {
  const PasswordHasher({this.iterations = 1200000});

  final int iterations;

  static const algorithm = 'pbkdf2_sha256';

  Future<String> hash(String password, {String? salt}) async {
    salt ??= _salt();
    final derived = await _derive(password, salt, iterations);
    return '$algorithm\$$iterations\$$salt\$${base64.encode(derived)}';
  }

  /// Whether [password] matches [encoded]. Unknown algorithms, such as the
  /// `!` Django writes for unusable passwords, never match.
  Future<bool> verify(String password, String encoded) async {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != algorithm) return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds < 1) return false;
    final derived = await _derive(password, parts[2], rounds);
    return _constantTimeEquals(base64.encode(derived), parts[3]);
  }

  /// Whether [encoded] uses fewer rounds than this hasher, as Django checks
  /// to upgrade a hash on the next successful sign-in.
  bool mustUpdate(String encoded) {
    final parts = encoded.split(r'$');
    return parts.length == 4 &&
        parts[0] == algorithm &&
        (int.tryParse(parts[1]) ?? 0) < iterations;
  }

  static Future<Uint8List> _derive(String password, String salt, int rounds) =>
      Isolate.run(() async {
        final key = await Pbkdf2SecretKey.importRawKey(utf8.encode(password));
        return key.deriveBits(256, Hash.sha256, utf8.encode(salt), rounds);
      });

  static String _salt() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return String.fromCharCodes([
      for (var i = 0; i < 22; i++)
        alphabet.codeUnitAt(random.nextInt(alphabet.length)),
    ]);
  }
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
