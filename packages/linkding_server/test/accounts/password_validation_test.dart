import 'package:linkding_server/src/accounts/password_validation.dart';
import 'package:linkding_server/src/db/rows/rows.dart';
import 'package:test/test.dart';

/// The password validators linkding enables, with the messages Django 6.0
/// gave for the same passwords and user.
void main() {
  final validator = PasswordValidator.fromFile(
    'web/data/common-passwords.txt.gz',
  );
  final user = UserRow(
    id: 1,
    password: '',
    isSuperuser: true,
    username: 'admin',
    firstName: 'Ada',
    lastName: 'Lovelace',
    email: 'admin@example.org',
    isStaff: true,
    isActive: true,
    dateJoined: DateTime.utc(2026),
  );

  const fromDjango = {
    'admin': [
      'The password is too similar to the username.',
      'This password is too short. It must contain at least 8 characters.',
      'This password is too common.',
    ],
    '12345678901': [
      'This password is too common.',
      'This password is entirely numeric.',
    ],
    'Parity-pass-2026': <String>[],
    'lovelace99': ['The password is too similar to the last name.'],
    'example.org!': ['The password is too similar to the email address.'],
    'ÄDMIN': [
      'The password is too similar to the username.',
      'This password is too short. It must contain at least 8 characters.',
    ],
    '١٢٣٤٥٦٧٨٩': ['This password is entirely numeric.'],
    'PASSWORD ': ['This password is too common.'],
    'adalovelace': ['The password is too similar to the last name.'],
    'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxada': <String>[],
  };

  for (final MapEntry(key: password, value: messages) in fromDjango.entries) {
    test('"$password"', () {
      expect(validator.validate(password, user), messages);
    });
  }
}
