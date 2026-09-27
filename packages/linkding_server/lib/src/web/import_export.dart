import 'dart:convert';

import 'package:dust_server/server.dart';

import '../auth/sessions.dart';
import '../compat/form_data.dart';
import '../db/bookmarks_repo.dart';
import '../services/errors.dart';
import '../services/netscape.dart';
import 'context.dart';

/// linkding's `bookmark_import` and `bookmark_export`: bookmarks in and out
/// as a Netscape bookmarks file.
final class ImportExportViews {
  ImportExportViews(this.web);

  final Web web;

  /// `/settings/import`, reporting on the settings page.
  Future<Response> import(Request request) async {
    final c = await web.context(request);
    FormData? form;
    if (request.method == 'POST') {
      form = await readFormData(request);
      final failure = Sessions.csrfFailure(
        request,
        form['csrfmiddlewaretoken'],
      );
      if (failure != null) return csrfFailurePage(c, failure);
    }
    if (!c.isAuthenticated) return redirectToLogin(c);

    Future<void> say(String message, {bool error = false}) => web.addMessage(
      c,
      message,
      level: error ? 'error' : 'success',
      extraTags: error ? 'settings_error_message' : 'settings_success_message',
    );

    final file = form?.files['import_file'];
    if (file == null) {
      await say('Please select a file to import.', error: true);
      return c.redirect('/settings/general');
    }
    try {
      final result = await importNetscape(
        web.database.connection,
        utf8.decode(file.bytes),
        c.user!.id,
        mapPrivateFlag: form!['map_private_flag'] == 'on',
        disableUrlValidation: web.config.disableUrlValidation,
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
    return c.redirect('/settings/general');
  }

  /// `/settings/export`: every bookmark of the user as a download.
  Future<Response> export(Request request) async {
    final c = await web.context(request);
    if (!c.isAuthenticated) return redirectToLogin(c);
    final user = c.user!;
    final bookmarks = (await BookmarksRepo(
      web.database.connection,
    ).allOwned(user.id)).orThrow;
    final tags = await web.bookmarks.tagNames([
      for (final b in bookmarks) b.id,
    ]);
    final now = DateTime.now().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    final filename =
        'bookmarks_${now.year}-${two(now.month)}-${two(now.day)}_'
        '${two(now.hour)}-${two(now.minute)}-${two(now.second)}.html';
    return Response(
      200,
      body: exportNetscape(bookmarks, tags),
      headers: {
        'content-type': 'text/plain; charset=UTF-8',
        'content-disposition': 'attachment; filename="$filename"',
      },
    );
  }
}
