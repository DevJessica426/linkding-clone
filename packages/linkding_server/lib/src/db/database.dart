import 'package:dust_dart/db.dart';
import 'package:dust_db_postgres/dust_db_postgres.dart';

part 'database.g.dart';

/// The linkding database: connecting, migrating, closing.
///
/// `migrations/` recreates linkding's own PostgreSQL schema table for table
/// (checked against a real linkding database with pg_dump), plus one table
/// of the clone's own for sessions. `dust db build` embeds the files, and
/// [migrate] applies what is missing under an advisory lock.
@SqlxDatabase(type: SqlxDatabaseType.postgres, migrations: './migrations')
abstract class LinkdingDatabase implements DatabaseClient {
  /// Opens a pool on [url], e.g.
  /// `postgres://linkding:secret@localhost:5432/linkding?sslmode=disable`.
  factory LinkdingDatabase.connect(String url, {PgConnectOptions? options}) =
      _$LinkdingDatabase.connect;

  @override
  Connection get connection;
}
