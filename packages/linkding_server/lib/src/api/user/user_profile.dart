import 'package:dust_server/server.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../../config.dart';
import '../errors.dart';
import '../lookups.dart';

/// `GET /api/user/profile/`.
Future<Response> userProfile(Request request) async {
  final user = await apiUserOf(request);
  final profile = await profileOf(await apiDb(request), user.id);
  final row = profile.row;
  return apiJson(
    UserProfile(
      theme: row.theme,
      bookmarkDateDisplay: row.bookmarkDateDisplay,
      bookmarkLinkTarget: row.bookmarkLinkTarget,
      webArchiveIntegration: row.webArchiveIntegration,
      tagSearch: row.tagSearch,
      enableSharing: row.enableSharing,
      enablePublicSharing: row.enablePublicSharing,
      enableFavicons: row.enableFavicons,
      displayUrl: row.displayUrl,
      permanentNotes: row.permanentNotes,
      searchPreferences: profile.searchPreferences,
      version: linkdingVersion,
    ).toJson(),
  );
}
