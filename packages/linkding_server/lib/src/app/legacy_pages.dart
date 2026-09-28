import 'package:dust_server/server.dart';

import '../web/bookmark_form.dart';
import '../web/bookmark_views.dart';
import '../web/bundle_views.dart';
import '../web/context.dart';

/// The pages still written as view classes, until each moves to its
/// feature's handlers.
Router legacyPages(Web web) {
  final lists = BookmarkViews(web);
  final forms = BookmarkFormViews(web);
  final bundles = BundleViews(web);
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
    ..route('/bundles', any(bundles.index))
    ..route('/bundles/action', any(bundles.action))
    ..route('/bundles/new', any(bundles.create))
    ..route('/bundles/{id|[0-9]+}/edit', any(bundles.edit))
    ..route('/bundles/preview', any(bundles.preview));
}
