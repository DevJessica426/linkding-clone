import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

/// Django's default password hasher, `pbkdf2_sha256`.
///
/// Hashes are stored as `pbkdf2_sha256$<iterations>$<salt>$<base64 hash>`,
/// exactly as linkding stores them, so users of an existing linkding
/// database sign in with their existing passwords, and linkding accepts
/// passwords set here.
///
/// Django's 1,200,000 rounds of HMAC-SHA256 are slow on purpose. This
/// implementation computes the key's inner and outer SHA-256 states once and
/// runs two compressions per round on raw 32-bit words, then does the work
/// in a background isolate so the server keeps answering while it runs.
final class PasswordHasher {
  const PasswordHasher({this.iterations = 1200000});

  final int iterations;

  static const algorithm = 'pbkdf2_sha256';

  Future<String> hash(String password, {String? salt}) async {
    salt ??= _salt();
    final rounds = iterations;
    final derived = await Isolate.run(
      () => pbkdf2Sha256(utf8.encode(password), utf8.encode(salt!), rounds),
    );
    return '$algorithm\$$rounds\$$salt\$${base64.encode(derived)}';
  }

  /// Whether [password] matches [encoded]. Unknown algorithms, such as the
  /// `!` Django writes for unusable passwords, never match.
  Future<bool> verify(String password, String encoded) async {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != algorithm) return false;
    final rounds = int.tryParse(parts[1]);
    if (rounds == null || rounds < 1) return false;
    final salt = parts[2];
    final derived = await Isolate.run(
      () => pbkdf2Sha256(utf8.encode(password), utf8.encode(salt), rounds),
    );
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

/// PBKDF2-HMAC-SHA256 with a 32-byte output, which is all Django asks for.
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations) {
  var key = Uint8List.fromList(password);
  if (key.length > 64) key = _Sha256.digest(key);
  final block = Uint8List(64)..setAll(0, key);
  final ipad = Uint8List(64);
  final opad = Uint8List(64);
  for (var i = 0; i < 64; i++) {
    ipad[i] = block[i] ^ 0x36;
    opad[i] = block[i] ^ 0x5c;
  }
  // The states after absorbing the padded key, shared by every round.
  final innerState = _Sha256.initial()..compressBytes(ipad, 0);
  final outerState = _Sha256.initial()..compressBytes(opad, 0);

  // U1 = HMAC(password, salt || INT(1)).
  final first = BytesBuilder()
    ..add(salt)
    ..add(const [0, 0, 0, 1]);
  final u1 = _hmacFromStates(innerState, outerState, first.toBytes());

  final u = Uint32List(8);
  final result = Uint32List(8);
  for (var i = 0; i < 8; i++) {
    u[i] = _readWord(u1, i * 4);
    result[i] = u[i];
  }

  // Every further round hashes a 32-byte value, which fits one padded block:
  // inner = SHA256(ipad-state, U || 0x80 || 0... || len), then the outer.
  final message = Uint32List(16);
  message[8] = 0x80000000;
  message[15] = (64 + 32) * 8;
  final inner = Uint32List(8);
  final outer = Uint32List(8);
  final w = Uint32List(64);
  for (var round = 1; round < iterations; round++) {
    for (var i = 0; i < 8; i++) {
      message[i] = u[i];
    }
    inner.setAll(0, innerState.h);
    _Sha256.compressWords(inner, message, w);
    for (var i = 0; i < 8; i++) {
      message[i] = inner[i];
    }
    outer.setAll(0, outerState.h);
    _Sha256.compressWords(outer, message, w);
    for (var i = 0; i < 8; i++) {
      u[i] = outer[i];
      result[i] ^= outer[i];
    }
  }

  final out = Uint8List(32);
  for (var i = 0; i < 8; i++) {
    _writeWord(out, i * 4, result[i]);
  }
  return out;
}

Uint8List _hmacFromStates(_Sha256 inner, _Sha256 outer, List<int> message) {
  final innerDigest = inner.copy().finish(message, alreadyHashed: 64);
  return outer.copy().finish(innerDigest, alreadyHashed: 64);
}

int _readWord(List<int> bytes, int at) =>
    (bytes[at] << 24) |
    (bytes[at + 1] << 16) |
    (bytes[at + 2] << 8) |
    bytes[at + 3];

void _writeWord(Uint8List bytes, int at, int word) {
  bytes[at] = (word >> 24) & 0xff;
  bytes[at + 1] = (word >> 16) & 0xff;
  bytes[at + 2] = (word >> 8) & 0xff;
  bytes[at + 3] = word & 0xff;
}

/// SHA-256 with access to the intermediate state.
final class _Sha256 {
  _Sha256(this.h);

  factory _Sha256.initial() => _Sha256(
    Uint32List.fromList(const [
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
      0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]),
  );

  final Uint32List h;

  _Sha256 copy() => _Sha256(Uint32List.fromList(h));

  static Uint8List digest(List<int> data) =>
      _Sha256.initial().finish(data, alreadyHashed: 0);

  void compressBytes(List<int> block, int offset) {
    final m = Uint32List(16);
    for (var i = 0; i < 16; i++) {
      m[i] = _readWord(block, offset + i * 4);
    }
    compressWords(h, m, Uint32List(64));
  }

  /// Pads [data] as the last part of a message that already absorbed
  /// [alreadyHashed] bytes, and returns the digest.
  Uint8List finish(List<int> data, {required int alreadyHashed}) {
    final total = alreadyHashed + data.length;
    final padded = BytesBuilder()
      ..add(data)
      ..addByte(0x80);
    while ((padded.length + 8) % 64 != 0) {
      padded.addByte(0);
    }
    final bits = total * 8;
    padded.add([
      (bits >> 56) & 0xff, (bits >> 48) & 0xff, (bits >> 40) & 0xff, //
      (bits >> 32) & 0xff, (bits >> 24) & 0xff, (bits >> 16) & 0xff,
      (bits >> 8) & 0xff, bits & 0xff,
    ]);
    final bytes = padded.toBytes();
    for (var at = 0; at < bytes.length; at += 64) {
      compressBytes(bytes, at);
    }
    final out = Uint8List(32);
    for (var i = 0; i < 8; i++) {
      _writeWord(out, i * 4, h[i]);
    }
    return out;
  }

  static const _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, //
    0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
    0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
    0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

  /// One compression of [m] (16 words) into [state], using [w] as scratch.
  static void compressWords(Uint32List state, Uint32List m, Uint32List w) {
    for (var i = 0; i < 16; i++) {
      w[i] = m[i];
    }
    for (var i = 16; i < 64; i++) {
      final a = w[i - 15], b = w[i - 2];
      final s0 = _rotr(a, 7) ^ _rotr(a, 18) ^ (a >> 3);
      final s1 = _rotr(b, 17) ^ _rotr(b, 19) ^ (b >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
    }
    var a = state[0], b = state[1], c = state[2], d = state[3];
    var e = state[4], f = state[5], g = state[6], hh = state[7];
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & 0xffffffff & g);
      final t1 = (hh + s1 + ch + _k[i] + w[i]) & 0xffffffff;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    state[0] = (state[0] + a) & 0xffffffff;
    state[1] = (state[1] + b) & 0xffffffff;
    state[2] = (state[2] + c) & 0xffffffff;
    state[3] = (state[3] + d) & 0xffffffff;
    state[4] = (state[4] + e) & 0xffffffff;
    state[5] = (state[5] + f) & 0xffffffff;
    state[6] = (state[6] + g) & 0xffffffff;
    state[7] = (state[7] + hh) & 0xffffffff;
  }
}
