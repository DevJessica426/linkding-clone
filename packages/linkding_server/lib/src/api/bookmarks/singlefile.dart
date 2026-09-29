import 'package:dust_server/server.dart';

import '../../assets/asset_service.dart';
import '../../bookmarks/service/bookmark_service.dart';
import '../../config.dart';
import '../../core/urls.dart';
import '../../db/repos/bookmarks_repo.dart';
import '../../db/or_throw.dart';
import '../body.dart';
import '../errors.dart';
import '../lookups.dart';

/// `POST /api/bookmarks/singlefile/`: the browser extension's saved copy of
/// a page, as the latest snapshot of that URL's bookmark, which is created
/// when there is none.
Future<Response> uploadSinglefile(Request request) async {
  final config = await request.state<ServerConfig>();
  if (config.disableAssetUpload) {
    throw ApiException(403, const {'error': 'Asset upload is disabled.'});
  }
  final db = await apiDb(request);
  final user = await apiUserOf(request);
  // `request.POST` and `request.FILES`: empty for a JSON body.
  final body = await readRequestBody(request);
  final url = body.form?['url']?.last;
  final file = body.files['file'];
  if (url == null || url.isEmpty || file == null) {
    throw ApiException(400, const {
      'error': "Both 'url' and 'file' parameters are required.",
    });
  }
  var bookmark = (await BookmarksRepo(
    db,
  ).existing(user.id, normalizeUrl(url), url)).orThrow;
  bookmark ??= await (await request.state<BookmarkService>()).create(
    BookmarkDraft(url: url),
    '',
    user.id,
    await profileOf(db, user.id),
    scrape: config.enableMetadataScraping,
  );
  await (await request.state<AssetService>()).uploadSnapshot(
    bookmark,
    file.bytes,
  );
  return apiJson({'message': 'Snapshot uploaded successfully.'}, status: 201);
}
