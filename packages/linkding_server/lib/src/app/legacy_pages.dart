import 'package:dust_server/server.dart';

import '../web/asset_views.dart';
import '../web/bookmark_form.dart';
import '../web/bookmark_views.dart';
import '../web/bundle_views.dart';
import '../web/context.dart';
import '../web/import_export.dart';
import '../web/settings_views.dart';
import '../web/tag_views.dart';

/// The pages still written as view classes, until each moves to its
/// feature's handlers.
Router legacyPages(Web web) {
  final lists = BookmarkViews(web);
  final files = AssetViews(web);
  final forms = BookmarkFormViews(web);
  final tags = TagViews(web);
  final bundles = BundleViews(web);
  final settings = SettingsViews(web);
  final transfer = ImportExportViews(web);
  return Router()
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
    ..route('/assets/{id|[0-9]+}/read', any(files.read));
}
