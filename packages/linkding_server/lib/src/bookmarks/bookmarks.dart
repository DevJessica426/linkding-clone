/// linkding's bookmark pages: the three lists and what their forms post,
/// the details modal, and the new and edit forms.
library;

import 'package:dust_server/server.dart';

import '../pages/sign_in.dart';
import 'form_handlers.dart';
import 'list_actions.dart';
import 'list_handlers.dart';

export 'bookmark_access.dart';
export 'list_kind.dart';
export 'list_links.dart';
export 'list_loader.dart' show searchList;
export 'list_page.dart';
export 'list_values.dart';
export 'tag_cloud.dart';

Router bookmarkRoutes() => Router()
  ..merge(
    Router()
      ..routeLayer(fromExtractor(const RequireSignIn()))
      ..route('/bookmarks', any(activeList))
      ..route('/bookmarks/action', any(activeAction))
      ..route('/bookmarks/archived', any(archivedList))
      ..route('/bookmarks/archived/action', any(archivedAction))
      ..route('/bookmarks/shared/action', any(sharedAction))
      ..route('/bookmarks/new', any(newBookmark))
      ..route('/bookmarks/close', any(closeBookmark))
      ..route('/bookmarks/{id|[0-9]+}/edit', any(editBookmark)),
  )
  ..route('/bookmarks/shared', any(sharedList));
