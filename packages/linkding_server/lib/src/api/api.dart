/// linkding's REST API under `/api`, at linkding's paths.
library;

import 'package:dust_server/server.dart';

import 'bookmarks/asset_endpoints.dart';
import 'bookmarks/bookmark_actions.dart';
import 'bookmarks/bookmark_lists.dart';
import 'bundles/bundle_endpoints.dart';
import 'bookmarks/singlefile.dart';
import 'tags/tag_endpoints.dart';
import 'user/user_profile.dart';
import 'view.dart';

export 'view.dart' show appendSlash;

// One path segment without a dot, as DRF's router matches ids. The slash is
// written as `\x2f`: dust_server never matches a pattern containing `/`.
const _id = r'{id|[^.\x2f]+}';

/// Django's `<int:bookmark_id>` in the nested asset routes.
const _bookmarkId = r'{bookmark_id|[0-9]+}';

/// `/api/` itself, which lists nothing. Mounted by the app, because a
/// nested router's own root has no trailing slash.
final apiRoot = apiView({'GET': apiIndex});

/// Every route, each with the slash-less form redirecting to it as
/// Django's `APPEND_SLASH` does. Authentication, method checks and errors
/// are [apiView]'s.
Router apiRoutes() {
  final routes = <String, Map<String, ApiHandler>>{
    '/bookmarks/': {'GET': listActive, 'POST': createBookmark},
    '/bookmarks/archived/': {'GET': listArchived},
    '/bookmarks/shared/': {'GET': listShared},
    '/bookmarks/check/': {'GET': checkBookmark},
    '/bookmarks/singlefile/': {'POST': uploadSinglefile},
    '/bookmarks/$_id/': {
      'GET': retrieveBookmark,
      'PUT': replaceBookmark,
      'PATCH': patchBookmark,
      'DELETE': deleteBookmark,
    },
    '/bookmarks/$_id/archive/': {'POST': archiveBookmark},
    '/bookmarks/$_id/unarchive/': {'POST': unarchiveBookmark},
    '/bookmarks/$_bookmarkId/assets/': {'GET': listAssets},
    '/bookmarks/$_bookmarkId/assets/upload/': {'POST': uploadAsset},
    '/bookmarks/$_bookmarkId/assets/$_id/': {
      'GET': retrieveAsset,
      'DELETE': deleteAsset,
    },
    '/bookmarks/$_bookmarkId/assets/$_id/download/': {'GET': downloadAsset},
    '/tags/': {'GET': listTags, 'POST': createTag},
    '/tags/$_id/': {'GET': retrieveTag, 'DELETE': deleteTag},
    '/bundles/': {'GET': listBundles, 'POST': createBundle},
    '/bundles/$_id/': {
      'GET': retrieveBundle,
      'PUT': replaceBundle,
      'PATCH': patchBundle,
      'DELETE': deleteBundle,
    },
    '/user/profile/': {'GET': userProfile},
  };
  final router = Router();
  for (final MapEntry(key: path, value: methods) in routes.entries) {
    router
      ..route(
        path,
        any(apiView(methods, anonymous: path == '/bookmarks/shared/')),
      )
      ..route(path.substring(0, path.length - 1), any(appendSlash));
  }
  return router;
}
