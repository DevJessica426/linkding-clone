import 'dart:async';

import 'package:dust_server/server.dart';

import '../../compat/form_data.dart';
import '../../db/database.dart';
import '../../pages/support/query_params.dart';
import '../../pages/session/visitor.dart';
import '../../search/search.dart';
import '../service/bookmark_service.dart';
import 'list_kind.dart';
import 'list_loader.dart';

/// The bulk edit bar's action on the ticked bookmarks, or on every one the
/// list's search matches.
Future<void> applyBulkAction(
  Request request,
  ListKind kind,
  int userId,
  FormData form,
) async {
  final bookmarks = await request.state<BookmarkService>();
  final ids = form['bulk_select_across'] == 'on'
      ? await _allMatching(request, kind)
      : [for (final id in form.list('bookmark_id')) ?int.tryParse(id.trim())];
  final tagString = (form['bulk_tag_string'] ?? '').replaceAll(' ', ',');
  switch (form['bulk_action']) {
    case 'bulk_archive':
      await bookmarks.setArchived(userId, ids, true);
    case 'bulk_unarchive':
      await bookmarks.setArchived(userId, ids, false);
    case 'bulk_delete':
      await bookmarks.delete(userId, ids);
    case 'bulk_tag':
      await bookmarks.tag(userId, ids, tagString);
    case 'bulk_untag':
      await bookmarks.untag(userId, ids, tagString);
    case 'bulk_read':
      await bookmarks.setUnread(userId, ids, false);
    case 'bulk_unread':
      await bookmarks.setUnread(userId, ids, true);
    case 'bulk_share':
      await bookmarks.setShared(userId, ids, true);
    case 'bulk_unshare':
      await bookmarks.setShared(userId, ids, false);
    case 'bulk_refresh':
      // A background task in linkding: the page does not wait for it.
      unawaited(
        bookmarks.refreshMetadata(userId, ids).catchError((Object _) {}),
      );
  }
}

/// Every bookmark the list's current search matches, for "select all".
Future<List<int>> _allMatching(Request request, ListKind kind) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final db = (await request.state<LinkdingDatabase>()).connection;
  final user = visitor.signedIn;
  final search = await BookmarkSearch.fromQuery(
    db,
    QueryParams.parse(request.requestedUri.query).last,
    ownerId: user.id,
    preferences: visitor.profile.searchPreferences,
  );
  final matches = await searchList(
    db,
    kind,
    search,
    visitor.profile,
    ownerId: user.id,
  );
  return [for (final m in matches) m.row.id];
}
