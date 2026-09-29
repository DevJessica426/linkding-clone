/// linkding's bookmark pages: the three lists and what their forms post,
/// the details modal, and the new and edit forms.
library;

import 'package:dust_server/server.dart';

import '../pages/session/sign_in.dart';
import 'forms/form_handlers.dart';
import 'lists/list_actions.dart';
import 'lists/list_handlers.dart';

export 'details/details.dart';
export 'forms/forms.dart';
export 'lists/lists.dart';
export 'service/service.dart';

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
