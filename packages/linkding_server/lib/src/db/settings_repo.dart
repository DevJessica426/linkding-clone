import 'package:dust_dart/db.dart';

import 'rows.dart';

part 'settings_repo.g.dart';

/// Instance-wide settings and per-user notices.
@SqlxDao()
abstract final class SettingsRepo {
  const factory SettingsRepo(Executor db) = _$SettingsRepo;

  @Query(r'''
SELECT id, landing_page, guest_profile_user_id, enable_link_prefetch
FROM bookmarks_globalsettings ORDER BY id LIMIT 1
''')
  Future<Result<GlobalSettingsRow?, SqlxError>> global();

  @Query(r'''
INSERT INTO bookmarks_globalsettings (landing_page, guest_profile_user_id,
                                      enable_link_prefetch)
SELECT 'login', NULL, false
WHERE NOT EXISTS (SELECT 1 FROM bookmarks_globalsettings)
''')
  Future<Result<Unit, SqlxError>> ensureGlobal();

  @Query(r'''
UPDATE bookmarks_globalsettings SET landing_page = $2,
  guest_profile_user_id = $3, enable_link_prefetch = $4
WHERE id = $1
''')
  Future<Result<Unit, SqlxError>> updateGlobal(
    int id,
    String landingPage,
    int? guestProfileUserId,
    bool enableLinkPrefetch,
  );

  @Query(r'''
SELECT id, key, message, acknowledged, owner_id FROM bookmarks_toast
WHERE owner_id = $1 AND NOT acknowledged ORDER BY id
''')
  Future<Result<List<ToastRow>, SqlxError>> toasts(int ownerId);

  @Query(r'''
INSERT INTO bookmarks_toast (key, message, acknowledged, owner_id)
VALUES ($1, $2, false, $3)
''')
  Future<Result<Unit, SqlxError>> addToast(
    String key,
    String message,
    int ownerId,
  );

  @Query(r'''
UPDATE bookmarks_toast SET acknowledged = true WHERE id = $1 AND owner_id = $2
''')
  Future<Result<Unit, SqlxError>> acknowledge(int id, int ownerId);
}
