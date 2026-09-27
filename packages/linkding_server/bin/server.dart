import 'dart:io';

import 'package:dust_server/server.dart';
import 'package:linkding_server/linkding_server.dart';

/// Serves linkding: `dart run packages/linkding_server/bin/server.dart`.
///
/// Configured with linkding's own environment variables (`LD_DB_*`,
/// `LD_SERVER_PORT`, `LD_SUPERUSER_NAME`, ...) or `DATABASE_URL`.
Future<void> main() async {
  final config = ServerConfig.fromEnvironment();
  final database = LinkdingDatabase.connect(config.databaseUrl);
  try {
    await prepareDatabase(database, config);
  } on Object catch (error) {
    stderr.writeln(
      'database setup failed on ${config.redactedDatabaseUrl}: $error',
    );
    await database.connection.close();
    exitCode = 1;
    return;
  }

  final http = GuardedHttpClient(Allowlist(config.allowedInternalHosts));
  final app = buildApp(
    database: database,
    config: config,
    metadata: config.enableMetadataScraping
        ? HttpWebsiteMetadataLoader(http)
        : const NoWebsiteMetadataLoader(),
  );
  final server = await serve(
    app,
    InternetAddress.tryParse(config.host) ?? InternetAddress.anyIPv4,
    config.port,
  );
  stdout
    ..writeln(
      'linkding (Dart clone of $linkdingVersion) listening on '
      'http://localhost:${server.port}',
    )
    ..writeln('  database  ${config.redactedDatabaseUrl}');

  await Future.any([
    ProcessSignal.sigint.watch().first,
    if (!Platform.isWindows) ProcessSignal.sigterm.watch().first,
  ]);
  await server.close(drain: const Duration(seconds: 10));
  http.close();
  await database.connection.close();
}
