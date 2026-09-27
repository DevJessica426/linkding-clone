import 'package:dust_dart/serde.dart';

part 'profile.g.dart';

/// `GET /api/user/profile/`: the preferences clients adapt to.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
@SerDe(renameAll: SerDeRename.snakeCase)
final class UserProfile with _$UserProfile {
  const UserProfile({
    required this.theme,
    required this.bookmarkDateDisplay,
    required this.bookmarkLinkTarget,
    required this.webArchiveIntegration,
    required this.tagSearch,
    required this.enableSharing,
    required this.enablePublicSharing,
    required this.enableFavicons,
    required this.displayUrl,
    required this.permanentNotes,
    required this.searchPreferences,
    required this.version,
  });

  factory UserProfile.fromJson(Map<String, Object?> json) =>
      _$UserProfileFromJson(json);

  /// `auto`, `light` or `dark`.
  final String theme;

  /// `relative`, `absolute` or `hidden`.
  final String bookmarkDateDisplay;

  /// `_blank` or `_self`.
  final String bookmarkLinkTarget;

  /// `enabled` or `disabled`.
  final String webArchiveIntegration;

  /// `strict`, or `lax` where a plain word also matches a tag of that name.
  final String tagSearch;

  final bool enableSharing;
  final bool enablePublicSharing;
  final bool enableFavicons;
  final bool displayUrl;
  final bool permanentNotes;

  /// The sort and filters last saved as defaults: `sort`, `shared`, `unread`.
  /// Empty until the owner saves some.
  final Map<String, String> searchPreferences;

  /// The linkding version this server is compatible with.
  final String version;
}

/// `GET /health`.
@Derive([ToString(), Eq(), Serialize(), Deserialize()])
final class Health with _$Health {
  const Health({required this.version, required this.status});

  factory Health.fromJson(Map<String, Object?> json) => _$HealthFromJson(json);

  final String version;

  /// `healthy`, or `unhealthy` when the database cannot be reached.
  final String status;
}
