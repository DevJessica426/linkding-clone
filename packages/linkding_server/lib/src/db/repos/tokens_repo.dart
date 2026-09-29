import 'package:dust_dart/db.dart';

import '../rows/user_rows.dart';

part 'tokens_repo.g.dart';

/// API tokens and feed tokens.
@SqlxDao()
abstract final class TokensRepo {
  const factory TokensRepo(Executor db) = _$TokensRepo;

  @Query(r'''
INSERT INTO bookmarks_apitoken (key, name, created, user_id)
VALUES ($1, $2, $3, $4)
RETURNING id, key, name, created, user_id
''')
  Future<Result<ApiTokenRow, SqlxError>> insertApiToken(
    String key,
    String name,
    DateTime created,
    int userId,
  );

  @Query(r'''
SELECT id, key, name, created, user_id FROM bookmarks_apitoken
WHERE user_id = $1 ORDER BY created DESC, id DESC
''')
  Future<Result<List<ApiTokenRow>, SqlxError>> apiTokens(int userId);

  @Query(r'DELETE FROM bookmarks_apitoken WHERE id = $1 AND user_id = $2')
  Future<Result<Unit, SqlxError>> deleteApiToken(int id, int userId);

  @Query(r'SELECT key FROM bookmarks_feedtoken WHERE user_id = $1')
  Future<Result<String?, SqlxError>> feedToken(int userId);

  @Query(r'''
INSERT INTO bookmarks_feedtoken (key, created, user_id) VALUES ($1, $2, $3)
ON CONFLICT (user_id) DO NOTHING
''')
  Future<Result<Unit, SqlxError>> insertFeedToken(
    String key,
    DateTime created,
    int userId,
  );
}
