import 'dart:io';

import 'package:dust_server/server.dart';

import 'api/api.dart';
import 'auth/sessions.dart';
import 'config.dart';
import 'db/database.dart';
import 'db/settings_repo.dart';
import 'services/assets.dart';
import 'services/bookmarks.dart';
import 'services/website_loader.dart';
import 'web/auth_views.dart';
import 'web/bookmark_views.dart';
import 'web/context.dart';

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

  final web = Web(
    database: database,
    config: config,
    sessions: sessions,
    bookmarks: bookmarks,
    assets: AssetService(database.connection, '${config.dataDir}/assets'),
    metadata: metadata,
  );
  final auth = AuthViews(web);
  final lists = BookmarkViews(web);

  return Router(onError: onError ?? _reportToStderr)
    ..route('/', any(auth.root))
    ..route('/login/', any(auth.login))
    ..route('/login', any(_appendSlash))
    ..route('/logout/', any(auth.logout))
    ..route('/logout', any(_appendSlash))
    ..route('/bookmarks', any(lists.index))
    ..route('/bookmarks/action', any(lists.indexAction))
    ..route('/bookmarks/archived', any(lists.archived))
    ..route('/bookmarks/archived/action', any(lists.archivedAction))
    ..route('/bookmarks/shared', any(lists.shared))
    ..route('/bookmarks/shared/action', any(lists.sharedAction))
    ..mount('/static', staticFiles('${config.webRoot}/static'))
    ..route('/api/', any(api.root))
    ..route('/api', any(LinkdingApi.appendSlash))
    ..nest('/api', api.router())
    ..route('/health', get((request) => _health(database)))
    ..fallback((_) => notFoundPage());
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

/// Django's `APPEND_SLASH`: a path that only exists with a trailing slash
/// is redirected there, permanently.
Response _appendSlash(Request request) {
  final uri = request.requestedUri;
  return Response(
    301,
    headers: {
      'location': uri.hasQuery ? '${uri.path}/?${uri.query}' : '${uri.path}/',
      'content-type': 'text/html; charset=utf-8',
    },
  );
}

void _reportToStderr(Object error, StackTrace stack) {
  stderr
    ..writeln('unhandled error: $error')
    ..writeln(stack);
}
