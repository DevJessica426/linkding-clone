import 'dart:convert';

import '../db/rows.dart';

/// A user's preferences, read from `bookmarks_userprofile`.
extension type const Profile(ProfileRow row) {
  bool get laxTags => row.tagSearch == 'lax';
  bool get legacySearch => row.legacySearch;
  String get autoTaggingRules => row.autoTaggingRules;

  /// The saved sort and filters: `sort`, `shared` and `unread`, each only if
  /// the user saved one.
  Map<String, String> get searchPreferences {
    final decoded = jsonDecode(row.searchPreferencesJson);
    if (decoded is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in decoded.entries)
        if (key is String && value is String) key: value,
    };
  }
}
