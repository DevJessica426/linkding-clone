import 'dart:convert';
import 'dart:io';

import '../db/rows.dart';
import 'common_passwords.dart';

/// Django's `AUTH_PASSWORD_VALIDATORS` as linkding configures them: a new
/// password must not resemble the user's name or email, must have eight
/// characters, must not be a common password, and must not be all digits.
/// Returns every message, in the validators' order.
List<String> validatePassword(String password, UserRow user) => [
  ?_similarity(password, user),
  if (password.runes.length < 8)
    'This password is too short. It must contain at least 8 characters.',
  if (_commonPasswords.contains(password.toLowerCase().trim()))
    'This password is too common.',
  if (_numeric.hasMatch(password)) 'This password is entirely numeric.',
];

final _numeric = RegExp(r'^\p{Nd}+$', unicode: true);

final Set<String> _commonPasswords = {
  for (final line in const LineSplitter().convert(
    utf8.decode(
      gzip.decode(
        base64.decode(commonPasswordsGzipBase64.replaceAll('\n', '')),
      ),
    ),
  ))
    line.trim(),
};

/// `UserAttributeSimilarityValidator`: the first attribute, or part of one
/// between non-word characters, whose characters overlap the password's
/// by 70% or more.
String? _similarity(String password, UserRow user) {
  const maxSimilarity = 0.7;
  final lowered = password.toLowerCase();
  for (final (value, verboseName) in [
    (user.username, 'username'),
    (user.firstName, 'first name'),
    (user.lastName, 'last name'),
    (user.email, 'email address'),
  ]) {
    if (value.isEmpty) continue;
    final valueLower = value.toLowerCase();
    for (final part in [...valueLower.split(_nonWord), valueLower]) {
      if (_exceedsMaximumLengthRatio(lowered, maxSimilarity, part)) continue;
      if (_quickRatio(lowered, part) >= maxSimilarity) {
        return 'The password is too similar to the $verboseName.';
      }
    }
  }
  return null;
}

/// Python's `\W+` on text.
final _nonWord = RegExp(r'[^\p{L}\p{N}_]+', unicode: true);

/// Django's `exceeds_maximum_length_ratio`: a value far shorter than the
/// password cannot be similar enough to matter.
bool _exceedsMaximumLengthRatio(
  String password,
  double maxSimilarity,
  String value,
) {
  final passwordLength = password.runes.length;
  final valueLength = value.runes.length;
  return passwordLength >= 10 * valueLength &&
      valueLength < maxSimilarity / 2 * passwordLength;
}

/// `difflib.SequenceMatcher(a=a, b=b).quick_ratio()`: twice the characters
/// the two have in common, over their total length.
double _quickRatio(String a, String b) {
  final available = <int, int>{};
  for (final rune in b.runes) {
    available[rune] = (available[rune] ?? 0) + 1;
  }
  var matches = 0;
  for (final rune in a.runes) {
    final left = available[rune] ?? 0;
    available[rune] = left - 1;
    if (left > 0) matches++;
  }
  final length = a.runes.length + b.runes.length;
  return length == 0 ? 1.0 : 2.0 * matches / length;
}
