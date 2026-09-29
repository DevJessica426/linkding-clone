import 'package:dust_server/server.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../../assets/asset_service.dart';
import '../../config.dart';
import '../../db/repos/assets_repo.dart';
import '../../db/repos/bookmarks_repo.dart';
import '../../db/or_throw.dart';
import '../../db/rows/rows.dart';
import '../body.dart';
import '../errors.dart';
import '../lookups.dart';
import '../pagination.dart';

Map<String, Object?> _assetJson(AssetRow row) => BookmarkAsset(
  id: row.id,
  bookmark: row.bookmarkId,
  dateCreated: row.dateCreated,
  fileSize: row.fileSize,
  assetType: row.assetType,
  contentType: row.contentType,
  displayName: row.displayName,
  status: row.status,
).toJson();

final _uploadDisabled = ApiException(403, const {
  'error': 'Asset upload is disabled.',
});

/// `access.bookmark_write` for the nested asset routes, which answers
/// Django's own 404 message rather than DRF's.
Future<BookmarkRow> _assetBookmark(Request request, UserRow user) async {
  final id = int.tryParse(await request.path<String>('bookmark_id'));
  final row = id == null || id > 2147483647
      ? null
      : (await BookmarksRepo(await apiDb(request)).owned(id, user.id)).orThrow;
  if (row == null) throw ApiException.detail(404, 'Bookmark does not exist');
  return row;
}

Future<AssetRow> _ownedAsset(Request request, UserRow user) async {
  final bookmark = await _assetBookmark(request, user);
  final id = await pathId(request, 'BookmarkAsset');
  final row = (await AssetsRepo(
    await apiDb(request),
  ).ofBookmark(id, bookmark.id, user.id)).orThrow;
  if (row == null) throw ApiException.noMatch('BookmarkAsset');
  return row;
}

/// `GET /api/bookmarks/<id>/assets/`.
Future<Response> listAssets(Request request) async {
  final bookmark = await _assetBookmark(request, await apiUserOf(request));
  final page = LimitOffset.fromQuery(request.requestedUri.queryParameters);
  final rows = (await AssetsRepo(await apiDb(request)).forBookmark(bookmark.id))
      .orThrow;
  final url = request.requestedUri.toString();
  return apiJson({
    'count': rows.length,
    'next': page.next(url, rows.length),
    'previous': page.previous(url),
    'results': [
      for (final row in rows.skip(page.offset).take(page.limit))
        _assetJson(row),
    ],
  });
}

/// `GET /api/bookmarks/<id>/assets/<asset>/`.
Future<Response> retrieveAsset(Request request) async =>
    apiJson(_assetJson(await _ownedAsset(request, await apiUserOf(request))));

/// `DELETE /api/bookmarks/<id>/assets/<asset>/`.
Future<Response> deleteAsset(Request request) async {
  final asset = await _ownedAsset(request, await apiUserOf(request));
  await (await request.state<AssetService>()).remove(asset);
  return Response(204);
}

/// The file, unzipped, to save under the asset's name.
Future<Response> downloadAsset(Request request) async {
  final asset = await _ownedAsset(request, await apiUserOf(request));
  final content = await (await request.state<AssetService>()).read(asset);
  if (content == null) {
    throw ApiException.detail(404, 'Asset file does not exist');
  }
  return Response(
    200,
    body: content,
    headers: {
      'content-type': asset.contentType,
      'content-disposition':
          'attachment; filename="${AssetService.downloadName(asset)}"',
    },
  );
}

/// `POST /api/bookmarks/<id>/assets/upload/` with the file as `file`.
Future<Response> uploadAsset(Request request) async {
  if ((await request.state<ServerConfig>()).disableAssetUpload) {
    throw _uploadDisabled;
  }
  final bookmark = await _assetBookmark(request, await apiUserOf(request));
  final file = (await readRequestBody(request)).files['file'];
  if (file == null) {
    throw ApiException(400, const {'error': 'No file provided.'});
  }
  final asset = await (await request.state<AssetService>()).upload(
    bookmark,
    file.name,
    file.contentType,
    file.bytes,
  );
  return apiJson(_assetJson(asset), status: 201);
}
