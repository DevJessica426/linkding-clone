import 'package:dust_server/server.dart';

import '../../assets/asset_service.dart';
import '../../compat/form_data.dart';
import '../../config.dart';
import '../../db/repos/assets_repo.dart';
import '../../db/repos/bookmark_states_repo.dart';
import '../../db/repos/bookmarks_repo.dart';
import '../../db/database.dart';
import '../../db/or_throw.dart';
import '../../db/rows/rows.dart';
import '../service/bookmark_service.dart';
import 'bulk_actions.dart';
import 'list_kind.dart';

const _html = {'content-type': 'text/html; charset=utf-8'};

/// linkding's `handle_action`: what one button of the list or the details
/// modal asks for, or a bulk action. Returns a response only when the
/// action fails.
Future<Response?> applyAction(
  Request request,
  ListKind kind,
  int userId,
  FormData form,
) async {
  final db = (await request.state<LinkdingDatabase>()).connection;
  final bookmarks = await request.state<BookmarkService>();
  final repo = BookmarksRepo(db);

  /// Runs [action] on the user's bookmark named by the [key] field.
  Future<Response?> owned(
    String key,
    Future<void> Function(BookmarkRow bookmark) action,
  ) async {
    final id = int.tryParse(form[key] ?? '');
    final bookmark = id == null ? null : (await repo.owned(id, userId)).orThrow;
    if (bookmark == null) return _notFound;
    await action(bookmark);
    return null;
  }

  if (form.has('archive')) {
    return owned('archive', (b) => bookmarks.setArchived(userId, [b.id], true));
  }
  if (form.has('unarchive')) {
    return owned(
      'unarchive',
      (b) => bookmarks.setArchived(userId, [b.id], false),
    );
  }
  if (form.has('remove')) {
    return owned('remove', (b) => bookmarks.delete(userId, [b.id]));
  }
  if (form.has('mark_as_read')) {
    return owned(
      'mark_as_read',
      (b) async =>
          (await BookmarkStatesRepo(db).markRead(b.id, userId)).orThrow,
    );
  }
  if (form.has('unshare')) {
    return owned(
      'unshare',
      (b) async => (await BookmarkStatesRepo(
        db,
      ).setState(b.id, userId, b.isArchived, b.unread, false)).orThrow,
    );
  }
  if (form.has('create_html_snapshot')) {
    // Snapshots need linkding's single-file tooling; like linkding without
    // LD_ENABLE_SNAPSHOTS, the request is accepted and nothing happens.
    return owned('create_html_snapshot', (_) async {});
  }
  if (form.has('upload_asset')) {
    if ((await request.state<ServerConfig>()).disableAssetUpload) {
      return Response(403, body: 'Asset upload is disabled', headers: _html);
    }
    final file = form.files['upload_asset_file'];
    final assets = await request.state<AssetService>();
    Response? missing;
    final notFound = await owned('upload_asset', (b) async {
      if (file == null) {
        missing = Response(400, body: 'No file provided', headers: _html);
        return;
      }
      await assets.upload(b, file.name, file.contentType, file.bytes);
    });
    return notFound ?? missing;
  }
  if (form.has('remove_asset')) {
    final id = int.tryParse(form['remove_asset'] ?? '');
    final asset = id == null
        ? null
        : (await AssetsRepo(db).owned(id, userId)).orThrow;
    if (asset == null) return _notFound;
    await (await request.state<AssetService>()).remove(asset);
    return null;
  }
  if (form.has('update_state')) {
    return owned(
      'update_state',
      (b) async => (await BookmarkStatesRepo(db).setState(
        b.id,
        userId,
        form['is_archived'] == 'on',
        form['unread'] == 'on',
        form['shared'] == 'on',
      )).orThrow,
    );
  }
  if (form.has('bulk_execute')) {
    await applyBulkAction(request, kind, userId, form);
  }
  return null;
}

Response get _notFound =>
    const Rejection.notFound('No Bookmark matches').intoResponse();
