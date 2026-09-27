import 'dart:io';
import 'dart:math';

import 'auth/passwords.dart';
import 'config.dart';
import 'db/database.dart';
import 'db/settings_repo.dart';
import 'db/users_repo.dart';
import 'services/errors.dart';

/// Migrations that create linkding's own tables. On a database a real
/// linkding created, they are recorded as applied instead of run.
const _linkdingSchema = [
  '20260927000001_create_users.up.sql',
  '20260927000002_create_user_profiles.up.sql',
  '20260927000003_create_tags.up.sql',
  '20260927000004_create_bookmarks.up.sql',
  '20260927000005_create_bundles.up.sql',
  '20260927000006_create_tokens.up.sql',
  '20260927000007_create_settings_and_toasts.up.sql',
];

/// Brings the database up to date and creates the configured superuser.
Future<void> prepareDatabase(
  LinkdingDatabase database,
  ServerConfig config,
) async {
  await _adoptLinkdingDatabase(database);
  (await database.migrate()).orThrow;
  (await SettingsRepo(database.connection).ensureGlobal()).orThrow;
  await createInitialSuperuser(database, config);
}

/// A database linkding created already has its tables: marks the schema
/// migrations applied so only the clone's own tables are added.
Future<void> _adoptLinkdingDatabase(LinkdingDatabase database) async {
  // dust:allow-unsafe-sql
  final tables = (await database.unsafe.fetchAs<String>(
    'SELECT table_name::text AS name FROM information_schema.tables '
    'WHERE table_schema = current_schema() '
    "AND table_name IN ('django_migrations', '__dust_schema_migrations')",
    const [],
    (row) => row.read<String>('name'),
  )).orThrow;
  if (!tables.contains('django_migrations') ||
      tables.contains('__dust_schema_migrations')) {
    return;
  }
  stdout.writeln('adopting an existing linkding database');
  // dust:allow-unsafe-sql
  (await database.unsafe.execute(
    'CREATE TABLE __dust_schema_migrations ('
    'name TEXT PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT now())',
    const [],
  )).orThrow;
  for (final name in _linkdingSchema) {
    // dust:allow-unsafe-sql
    (await database.unsafe.execute(
      r'INSERT INTO __dust_schema_migrations (name) VALUES ($1)',
      [name],
    )).orThrow;
  }
}

/// linkding's `create_initial_superuser`: creates `LD_SUPERUSER_NAME` when
/// no user of that name exists, with an unusable password when none is set.
Future<void> createInitialSuperuser(
  LinkdingDatabase database,
  ServerConfig config,
) async {
  final name = config.superuserName;
  if (name == null || name.isEmpty) return;
  final users = UsersRepo(database.connection);
  if ((await users.byUsername(name)).orThrow != null) return;
  await createUser(
    database,
    config,
    username: name,
    password: config.superuserPassword,
    superuser: true,
  );
  stdout.writeln('created initial superuser $name');
}

/// Creates a user and their profile, as Django's user creation and
/// linkding's `post_save` signal do.
Future<int> createUser(
  LinkdingDatabase database,
  ServerConfig config, {
  required String username,
  String? password,
  bool superuser = false,
}) async {
  final hash = password == null || password.isEmpty
      ? _unusablePassword()
      : await PasswordHasher(iterations: config.passwordIterations)
            .hash(password);
  final users = UsersRepo(database.connection);
  final user = (await users.insert(
    hash,
    superuser,
    username,
    '',
    DateTime.now().toUtc(),
  )).orThrow;
  (await users.insertDefaultProfile(user.id)).orThrow;
  return user.id;
}

/// Django's `set_unusable_password`: `!` and 40 random characters.
String _unusablePassword() {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = Random.secure();
  return '!${String.fromCharCodes([for (var i = 0; i < 40; i++) chars.codeUnitAt(random.nextInt(chars.length))])}';
}
