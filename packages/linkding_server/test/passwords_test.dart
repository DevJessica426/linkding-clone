import 'package:linkding_server/src/auth/passwords.dart';
import 'package:test/test.dart';

/// Hashes in Django's format, checked against a hash real linkding wrote.
void main() {
  // linkding 1.47.0's hash for the password "admin12345", 1,200,000 rounds.
  const fromLinkding =
      r'pbkdf2_sha256$1200000$i7hz8EaGv1SbtSiDVI4nP6$NEH8tb4xFTf5EKii7IEpqJrSXG5LVGIigboscA9aSAM=';

  test('accepts a password hashed by linkding', () async {
    expect(
      await const PasswordHasher().verify('admin12345', fromLinkding),
      isTrue,
    );
    expect(
      await const PasswordHasher().verify('admin1234', fromLinkding),
      isFalse,
    );
  });

  test('round-trips its own hashes in Django format', () async {
    const hasher = PasswordHasher(iterations: 1000);
    final encoded = await hasher.hash('secret', salt: 'abc');
    expect(encoded, startsWith(r'pbkdf2_sha256$1000$abc$'));
    expect(await hasher.verify('secret', encoded), isTrue);
    expect(await hasher.verify('Secret', encoded), isFalse);
  });

  test('never matches unusable or foreign hashes', () async {
    const hasher = PasswordHasher();
    expect(await hasher.verify('x', '!unusable'), isFalse);
    expect(await hasher.verify('x', r'md5$$abc'), isFalse);
  });

  test('flags hashes with fewer rounds for upgrading', () {
    expect(
      const PasswordHasher().mustUpdate(r'pbkdf2_sha256$1000$s$h'),
      isTrue,
    );
    expect(const PasswordHasher().mustUpdate(fromLinkding), isFalse);
  });
}
