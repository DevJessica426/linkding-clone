import 'package:dust_dart/db.dart';

part 'sessions_repo.g.dart';

/// Browser sessions: the clone's own `clone_session` table.
@SqlxDao()
abstract final class SessionsRepo {
  const factory SessionsRepo(Executor db) = _$SessionsRepo;

  @Query(r'''
INSERT INTO clone_session (session_key, user_id, expire_date)
VALUES ($1, $2, $3)
''')
  Future<Result<Unit, SqlxError>> insertSession(
    String key,
    int userId,
    DateTime expires,
  );

  @Query(r'DELETE FROM clone_session WHERE session_key = $1')
  Future<Result<Unit, SqlxError>> deleteSession(String key);

  /// A session under a new key and expiry, its data kept: Django's
  /// `cycle_key`.
  @Query(r'''
UPDATE clone_session SET session_key = $2, expire_date = $3
WHERE session_key = $1
''')
  Future<Result<Unit, SqlxError>> renewSession(
    String key,
    String newKey,
    DateTime expires,
  );

  /// Every session of a user but [keep], after a password change.
  @Query(r'DELETE FROM clone_session WHERE user_id = $1 AND session_key <> $2')
  Future<Result<Unit, SqlxError>> deleteOtherSessions(int userId, String keep);

  @Query(r'DELETE FROM clone_session WHERE expire_date <= $1')
  Future<Result<Unit, SqlxError>> deleteExpiredSessions(DateTime now);
}
