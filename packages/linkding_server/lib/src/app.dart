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
import 'web/asset_views.dart';
import 'web/auth_views.dart';
import 'web/bookmark_form.dart';
import 'web/bookmark_views.dart';
import 'web/bundle_views.dart';
import 'web/context.dart';
import 'web/feeds.dart';
import 'web/import_export.dart';
import 'web/settings_views.dart';
import 'web/site_views.dart';
import 'web/tag_views.dart';

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
  final assets = AssetService(database.connection, '${config.dataDir}/assets');
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
  final auth = AuthViews(web);
  final lists = BookmarkViews(web);
  final files = AssetViews(web);
  final forms = BookmarkFormViews(web);
  final tags = TagViews(web);
  final bundles = BundleViews(web);
  final settings = SettingsViews(web);
  final transfer = ImportExportViews(web);
  final feeds = FeedViews(web);
  final site = SiteViews(web);

  return Router(onError: onError ?? _reportToStderr)
    ..route('/', any(auth.root))
    ..route('/login/', any(auth.login))
    ..route('/login', any(_appendSlash))
    ..route('/logout/', any(auth.logout))
    ..route('/logout', any(_appendSlash))
    ..route('/change-password/', any(auth.changePassword))
    ..route('/change-password', any(_appendSlash))
    ..route('/password-change-done/', any(auth.passwordChangeDone))
    ..route('/password-change-done', any(_appendSlash))
    ..route('/bookmarks', any(lists.index))
    ..route('/bookmarks/action', any(lists.indexAction))
    ..route('/bookmarks/archived', any(lists.archived))
    ..route('/bookmarks/archived/action', any(lists.archivedAction))
    ..route('/bookmarks/shared', any(lists.shared))
    ..route('/bookmarks/shared/action', any(lists.sharedAction))
    ..route('/bookmarks/new', any(forms.create))
    ..route('/bookmarks/close', any(forms.close))
    ..route('/bookmarks/{id|[0-9]+}/edit', any(forms.edit))
    ..route('/tags', any(tags.index))
    ..route('/tags/new', any(tags.create))
    ..route('/tags/{id|[0-9]+}/edit', any(tags.edit))
    ..route('/tags/merge', any(tags.merge))
    ..route('/bundles', any(bundles.index))
    ..route('/bundles/action', any(bundles.action))
    ..route('/bundles/new', any(bundles.create))
    ..route('/bundles/{id|[0-9]+}/edit', any(bundles.edit))
    ..route('/bundles/preview', any(bundles.preview))
    ..route('/settings', any(settings.general))
    ..route('/settings/general', any(settings.general))
    ..route('/settings/update', any(settings.update))
    ..route('/settings/integrations', any(settings.integrations))
    ..route(
      '/settings/integrations/create-api-token',
      any(settings.createApiToken),
    )
    ..route(
      '/settings/integrations/delete-api-token',
      any(settings.deleteApiToken),
    )
    ..route('/settings/import', any(transfer.import))
    ..route('/settings/export', any(transfer.export))
    ..route('/assets/{id|[0-9]+}', any(files.view))
    ..route('/assets/{id|[0-9]+}/read', any(files.read))
    ..route('/toasts/acknowledge', any(site.acknowledgeToast))
    ..route('/feeds/shared', any(feeds.publicShared))
    ..route('/feeds/{key}/all', any(feeds.all))
    ..route('/feeds/{key}/unread', any(feeds.unread))
    ..route('/feeds/{key}/shared', any(feeds.shared))
    ..route('/manifest.json', any(site.manifest))
    ..route('/custom_css', any(site.customCss))
    ..route('/opensearch.xml', any(site.opensearch))
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
