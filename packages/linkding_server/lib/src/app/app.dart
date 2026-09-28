import 'dart:io';

import 'package:dust_server/server.dart';

import '../accounts/accounts.dart';
import '../api/api.dart';
import '../assets/asset_pages.dart';
import '../auth/password_validation.dart';
import '../auth/passwords.dart';
import '../auth/sessions.dart';
import '../config.dart';
import '../db/database.dart';
import '../feeds/feeds.dart';
import '../pages/csrf_layer.dart';
import '../pages/error_pages.dart';
import '../pages/page_errors.dart';
import '../pages/visitor_layer.dart';
import '../services/assets.dart';
import '../services/bookmarks.dart';
import '../services/website_loader.dart';
import '../settings/settings.dart';
import '../site/site.dart';
import '../tags/tags.dart';
import '../web/context.dart';
import 'headers.dart';
import 'health.dart';
import 'legacy_pages.dart';

/// The whole application: the pages, the REST API under `/api`, the static
/// files, and the health check, with what they depend on attached as state.
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
  final assets = AssetService(database.connection, '${config.dataDir}/assets');
  final templates = MustacheTemplates.fromDirectory(
    '${config.webRoot}/templates',
  );
  final errors = ErrorPages(templates);
  final api = LinkdingApi(
    database: database,
    bookmarks: bookmarks,
    assets: assets,
    metadata: metadata,
    sessions: sessions,
    config: config,
  );
  final web = Web(
    database: database,
    config: config,
    sessions: sessions,
    bookmarks: bookmarks,
    assets: assets,
    metadata: metadata,
  );

  // Every page goes through Django's middleware, as layers: who the
  // visitor is, the CSRF check, and the error pages.
  final pages = Router()
    ..routeLayer(VisitorLayer(sessions, database.connection))
    ..routeLayer(CsrfProtection(errors))
    ..routeLayer(PageErrors(errors))
    ..merge(siteRoutes())
    ..merge(accountRoutes())
    ..merge(feedRoutes())
    ..merge(tagRoutes())
    ..merge(assetRoutes())
    ..merge(settingsRoutes())
    ..merge(legacyPages(web));

  return Router(onError: onError ?? _reportToStderr)
    ..layer(securityHeaders)
    ..layer(const OpenerPolicy())
    ..merge(pages)
    ..mount('/static', staticFiles('${config.webRoot}/static'))
    ..route('/api/', any(api.root))
    ..route('/api', any(LinkdingApi.appendSlash))
    ..nest('/api', api.router())
    ..route('/health', get(health))
    ..fallback((_) => errors.notFound())
    ..withState<LinkdingDatabase>(database)
    ..withState<ServerConfig>(config)
    ..withState<Sessions>(sessions)
    ..withState<TemplateEngine>(templates)
    ..withState<BookmarkService>(bookmarks)
    ..withState<AssetService>(assets)
    ..withState<WebsiteMetadataLoader>(metadata)
    ..withState(PasswordHasher(iterations: config.passwordIterations))
    ..withState(
      PasswordValidator.fromFile(
        '${config.webRoot}/data/common-passwords.txt.gz',
      ),
    );
}

void _reportToStderr(Object error, StackTrace stack) {
  stderr
    ..writeln('unhandled error: $error')
    ..writeln(stack);
}
