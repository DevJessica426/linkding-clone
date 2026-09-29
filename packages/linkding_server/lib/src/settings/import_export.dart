import 'dart:convert';

import 'package:dust_server/server.dart';

import '../bookmarks/service/bookmark_service.dart';
import '../compat/form_data.dart';
import '../config.dart';
import '../db/repos/bookmark_list_repo.dart';
import '../db/database.dart';
import '../db/or_throw.dart';
import '../netscape/netscape.dart';
import '../pages/session/session_data.dart';
import '../pages/session/visitor.dart';

/// `/settings/import`: bookmarks from a Netscape bookmarks file, reported
/// on the settings page.
Future<Response> importBookmarks(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final session = await SessionData.of(request);
  Future<void> say(String message, {bool error = false}) => session.addMessage(
    message,
    level: error ? 'error' : 'success',
    extraTags: error ? 'settings_error_message' : 'settings_success_message',
  );

  final form = await request.extract(const PostedForm());
  final file = form.files['import_file'];
  if (file == null) {
    await say('Please select a file to import.', error: true);
  } else {
    try {
      final result = await importNetscape(
        (await request.state<LinkdingDatabase>()).connection,
        utf8.decode(file.bytes),
        visitor.signedIn.id,
        mapPrivateFlag: form['map_private_flag'] == 'on',
        disableUrlValidation:
            (await request.state<ServerConfig>()).disableUrlValidation,
      );
      await say('${result.success} bookmarks were successfully imported.');
      if (result.failed > 0) {
        await say(
          '${result.failed} bookmarks could not be imported. Please check '
          'the logs for more details.',
          error: true,
        );
      }
    } on FormatException {
      await say('An error occurred during bookmark import.', error: true);
    }
  }
  return Redirect.found('/settings/general').intoResponse();
}

/// `/settings/export`: every bookmark of the user, as a download.
Future<Response> exportBookmarks(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final user = visitor.signedIn;
  final db = (await request.state<LinkdingDatabase>()).connection;
  final bookmarks = (await BookmarkListRepo(db).allOwned(user.id)).orThrow;
  final tags = await (await request.state<BookmarkService>()).tagNames([
    for (final b in bookmarks) b.id,
  ]);
  final now = DateTime.now().toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final filename =
      'bookmarks_${now.year}-${two(now.month)}-${two(now.day)}_'
      '${two(now.hour)}-${two(now.minute)}-${two(now.second)}.html';
  return Response.ok(
    exportNetscape(bookmarks, tags),
    headers: {
      'content-type': 'text/plain; charset=UTF-8',
      'content-disposition': 'attachment; filename="$filename"',
    },
  );
}
