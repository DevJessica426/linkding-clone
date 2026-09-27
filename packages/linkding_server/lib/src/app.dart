import 'dart:io';

import 'package:dust_server/server.dart';

import 'api/api.dart';
import 'auth/sessions.dart';
import 'config.dart';
import 'db/database.dart';
import 'db/settings_repo.dart';
import 'services/bookmarks.dart';
import 'services/website_loader.dart';

/// The whole application: the REST API under `/api`, the health check, and
/// (added by the web interface) every page.
Router buildApp({
  required LinkdingDatabase database,
  required ServerConfig config,
  required WebsiteMetadataLoader metadata,
  void Function(Object error, StackTrace stack)? onError,
}) {
  final sessions = Sessions(database.connection, age: config.sessionCookieAge);
  final bookmarks = BookmarkService(
    database,
    metadata,
    assetDir: '${config.dataDir}/assets',
  );
  final api = LinkdingApi(
    database: database,
    bookmarks: bookmarks,
    metadata: metadata,
    sessions: sessions,
    config: config,
  );

  return Router(onError: onError ?? _reportToStderr)
    ..route('/api/', any(api.root))
    ..route('/api', any(LinkdingApi.appendSlash))
    ..nest('/api', api.router())
    ..route('/health', get((request) => _health(database)))
    ..fallback(_notFound);
}

/// `GET /health`, byte for byte as linkding answers it.
Future<Response> _health(LinkdingDatabase database) async {
  final reachable = (await SettingsRepo(database.connection).global()).isOk;
  final status = reachable ? 'healthy' : 'unhealthy';
  return Response(
    reachable ? 200 : 500,
    body: '{"version": "$linkdingVersion", "status": "$status"}',
    headers: {'content-type': 'application/json'},
  );
}

/// Django's page for a path nothing serves.
Response _notFound(Request request) => Response(
  404,
  body:
      '\n<!doctype html>\n<html lang="en">\n<head>\n  <title>Not Found</title>\n'
      '</head>\n<body>\n  <h1>Not Found</h1><p>The requested resource was not '
      'found on this server.</p>\n</body>\n</html>\n',
  headers: {'content-type': 'text/html; charset=utf-8'},
);

void _reportToStderr(Object error, StackTrace stack) {
  stderr
    ..writeln('unhandled error: $error')
    ..writeln(stack);
}
