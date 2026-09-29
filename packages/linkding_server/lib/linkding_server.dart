/// linkding's server in Dart: its REST API and web interface over its own
/// PostgreSQL schema.
library;

import 'src/accounts/sessions.dart';
import 'src/db/database.dart';
import 'src/db/or_throw.dart';
import 'src/db/repos/tokens_repo.dart';
import 'src/db/repos/users_repo.dart';

export 'src/app/app.dart';
export 'src/config.dart';
export 'src/db/database.dart';
export 'src/metadata/http_client.dart' show Allowlist, GuardedHttpClient;
export 'src/metadata/website_loader.dart';
export 'src/startup.dart';

/// Creates an API token for [username] and returns its key.
Future<String> createApiToken(
  LinkdingDatabase database,
  String username,
  String name,
) async {
  final users = UsersRepo(database.connection);
  final user = (await users.byUsername(username)).orThrow;
  if (user == null) throw StateError('no user named $username');
  final token = (await TokensRepo(database.connection).insertApiToken(
    newTokenKey(),
    name,
    DateTime.now().toUtc(),
    user.id,
  )).orThrow;
  return token.key;
}
