import 'package:dust_dart/db.dart';

import '../rows/user_rows.dart';

part 'users_repo.g.dart';

/// Users: signing in, and who owns a token or a session.
@SqlxDao()
abstract final class UsersRepo {
  const factory UsersRepo(Executor db) = _$UsersRepo;

  /// Signing in: usernames are compared exactly, as Django does.
  @Query(r'''
SELECT id, password, last_login, is_superuser, username, first_name,
       last_name, email, is_staff, is_active, date_joined
FROM auth_user WHERE username = $1
''')
  Future<Result<UserRow?, SqlxError>> byUsername(String username);

  @Query(r'''
SELECT id, password, last_login, is_superuser, username, first_name,
       last_name, email, is_staff, is_active, date_joined
FROM auth_user WHERE id = $1
''')
  Future<Result<UserRow?, SqlxError>> byId(int id);

  /// The owner of an API token; the caller checks `is_active`.
  @Query(r'''
SELECT u.id, u.password, u.last_login, u.is_superuser, u.username,
       u.first_name, u.last_name, u.email, u.is_staff, u.is_active,
       u.date_joined
FROM bookmarks_apitoken t JOIN auth_user u ON u.id = t.user_id
WHERE t.key = $1
''')
  Future<Result<UserRow?, SqlxError>> byApiToken(String key);

  /// The owner of a session that has not expired.
  @Query(r'''
SELECT u.id, u.password, u.last_login, u.is_superuser, u.username,
       u.first_name, u.last_name, u.email, u.is_staff, u.is_active,
       u.date_joined
FROM clone_session s JOIN auth_user u ON u.id = s.user_id
WHERE s.session_key = $1 AND s.expire_date > $2
''')
  Future<Result<UserRow?, SqlxError>> bySession(String key, DateTime now);

  @Query(r'''
SELECT u.id, u.password, u.last_login, u.is_superuser, u.username,
       u.first_name, u.last_name, u.email, u.is_staff, u.is_active,
       u.date_joined
FROM bookmarks_feedtoken f JOIN auth_user u ON u.id = f.user_id
WHERE f.key = $1
''')
  Future<Result<UserRow?, SqlxError>> byFeedToken(String key);

  @Query(r'''
INSERT INTO auth_user (password, last_login, is_superuser, username,
                       first_name, last_name, email, is_staff, is_active,
                       date_joined)
VALUES ($1, NULL, $2, $3, '', '', $4, $2, true, $5)
RETURNING id, password, last_login, is_superuser, username, first_name,
          last_name, email, is_staff, is_active, date_joined
''')
  Future<Result<UserRow, SqlxError>> insert(
    String password,
    bool isSuperuser,
    String username,
    String email,
    DateTime dateJoined,
  );

  @Query(r'UPDATE auth_user SET password = $2 WHERE id = $1')
  Future<Result<Unit, SqlxError>> setPassword(int id, String password);

  @Query(r'UPDATE auth_user SET last_login = $2 WHERE id = $1')
  Future<Result<Unit, SqlxError>> setLastLogin(int id, DateTime at);

  @Query(
    r'SELECT id, username FROM auth_user WHERE is_active ORDER BY username',
  )
  Future<Result<List<UserNameRow>, SqlxError>> activeUsers();

  /// Every user, for choosing the guest profile, in table order as Django
  /// lists a query without an ordering.
  @Query(r'SELECT id, username FROM auth_user')
  Future<Result<List<UserNameRow>, SqlxError>> allUsers();

  @Query(r'SELECT id, username FROM auth_user WHERE id = ANY($1) ORDER BY id')
  Future<Result<List<UserNameRow>, SqlxError>> names(List<int> ids);
}
