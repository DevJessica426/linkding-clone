import 'dart:io';

import 'package:linkding_server/linkding_server.dart';

const _usage = '''
Administrative commands, like linkding's manage.py.

  manage.dart create_user <username> <password> [--superuser]
  manage.dart create_token <username> [name]    prints a new API token
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.write(_usage);
    exitCode = 2;
    return;
  }
  final config = ServerConfig.fromEnvironment();
  final database = LinkdingDatabase.connect(config.databaseUrl);
  try {
    await prepareDatabase(database, config);
    switch (args) {
      case ['create_user', final username, final password, ...final rest]:
        await createUser(
          database,
          config,
          username: username,
          password: password,
          superuser: rest.contains('--superuser'),
        );
        stdout.writeln('created $username');
      case ['create_token', final username, ...final rest]:
        stdout.writeln(
          await createApiToken(
            database,
            username,
            rest.isEmpty ? 'manage.dart' : rest.first,
          ),
        );
      default:
        stderr.write(_usage);
        exitCode = 2;
    }
  } finally {
    await database.connection.close();
  }
}
