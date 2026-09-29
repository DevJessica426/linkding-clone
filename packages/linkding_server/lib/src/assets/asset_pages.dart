import 'dart:convert';

import 'package:dust_server/server.dart';

import '../bookmarks/service/bookmark_access.dart';
import '../db/repos/assets_repo.dart';
import '../db/database.dart';
import '../db/or_throw.dart';
import '../db/rows/rows.dart';
import '../pages/support/render.dart';
import '../pages/session/visitor.dart';
import 'asset_service.dart';

/// linkding's `views/assets.py`: a bookmark's file, and a snapshot in
/// reader mode, for anyone who may see the bookmark.
Router assetRoutes() => Router()
  ..route('/assets/{id|[0-9]+}', any(viewAsset))
  ..route('/assets/{id|[0-9]+}/read', any(readAsset));

const _missing = Rejection.notFound('Asset does not exist');

/// `/assets/<id>`: the file itself, unzipped, shown in the browser.
Future<Result<Response, Rejection>> viewAsset(Request request) async {
  final (asset, content) = await _readable(request);
  if (asset == null || content == null) return const Err(_missing);
  return Ok(
    Response.ok(
      content,
      headers: {
        'content-type': asset.contentType,
        'content-disposition':
            'inline; filename="${AssetService.downloadName(asset)}"',
        'content-security-policy': _policy(asset.contentType),
      },
    ),
  );
}

/// `/assets/<id>/read`: a snapshot through Readability.js, in a sandboxed
/// page. The sandbox would send the custom CSS request without
/// credentials, so the CSS is embedded as a data URL.
Future<Result<Response, Rejection>> readAsset(Request request) async {
  final (asset, content) = await _readable(request);
  if (asset == null || content == null) return const Err(_missing);
  final visitor = await request.extract(const Extension<Visitor>());
  final css = visitor.profile.row.customCss;
  return Ok(
    render(await request.state<TemplateEngine>(), 'assets/reader', {
      ...layoutValues(visitor, title: 'Reader view'),
      'hasCustomCss': css.isNotEmpty,
      'customCssData': base64.encode(utf8.encode(css)),
      'content': utf8.decode(content),
    }).change(headers: {'content-security-policy': 'sandbox allow-scripts'}),
  );
}

/// `access.asset_read`, with the file's content.
Future<(AssetRow?, List<int>?)> _readable(Request request) async {
  final id = int.tryParse(await request.path<String>('id'));
  if (id == null || id > 2147483647) return (null, null);
  final db = (await request.state<LinkdingDatabase>()).connection;
  final asset = (await AssetsRepo(db).byId(id)).orThrow;
  if (asset == null) return (null, null);
  final visitor = await request.extract(const Extension<Visitor>());
  if (await readableBookmark(db, visitor, asset.bookmarkId) == null) {
    return (null, null);
  }
  return (asset, await (await request.state<AssetService>()).read(asset));
}

String _policy(String contentType) {
  if (contentType.startsWith('video/')) {
    return "default-src 'none'; media-src 'self';";
  }
  if (contentType == 'application/pdf') {
    return "default-src 'none'; object-src 'self';";
  }
  return 'sandbox allow-scripts';
}
