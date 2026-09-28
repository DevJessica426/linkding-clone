import 'package:dust_server/server.dart';

import '../config.dart';
import '../db/database.dart';
import '../db/settings_repo.dart';

/// `GET /health`, byte for byte as linkding answers it.
Future<Response> health(Request request) async {
  final database = await request.state<LinkdingDatabase>();
  final reachable = (await SettingsRepo(database.connection).global()).isOk;
  final status = reachable ? 'healthy' : 'unhealthy';
  return Response(
    reachable ? 200 : 500,
    body: '{"version": "$linkdingVersion", "status": "$status"}',
    headers: {'content-type': 'application/json'},
  );
}
