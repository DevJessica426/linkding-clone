import 'dart:convert';

import 'package:dust_server/server.dart';

import '../auth/sessions.dart';
import '../compat/django.dart';
import '../compat/form_data.dart';
import '../db/settings_repo.dart';
import '../services/errors.dart';
import 'bookmark_form.dart';
import 'context.dart';
import 'html.dart';

/// The small views around the pages: the web app manifest, the OpenSearch
/// description, the user's custom CSS, and dismissing a toast.
final class SiteViews {
  SiteViews(this.web);

  final Web web;

  /// `/manifest.json`, as Django's `JsonResponse` writes linkding's
  /// manifest.
  Future<Response> manifest(Request request) async {
    final c = await web.context(request);
    Map<String, String> icon(
      String src,
      String type,
      String sizes,
      String purpose,
    ) => {
      'src': '/static/$src',
      'type': type,
      'sizes': sizes,
      'purpose': purpose,
    };
    final manifest = {
      'short_name': 'linkding',
      'name': 'linkding',
      'description': 'Self-hosted bookmark service',
      'start_url': 'bookmarks',
      'display': 'standalone',
      'scope': '/',
      'theme_color': '#5856e0',
      'background_color': c.profile.row.theme == 'dark' ? '#161822' : '#ffffff',
      'icons': [
        icon('logo.svg', 'image/svg+xml', '512x512', 'any'),
        icon('logo-512.png', 'image/png', '512x512', 'any'),
        icon('logo-192.png', 'image/png', '192x192', 'any'),
        icon('maskable-logo.svg', 'image/svg+xml', '512x512', 'maskable'),
        icon('maskable-logo-512.png', 'image/png', '512x512', 'maskable'),
        icon('maskable-logo-192.png', 'image/png', '192x192', 'maskable'),
      ],
      'shortcuts': [
        {'name': 'Add bookmark', 'url': '/bookmarks/new'},
        {'name': 'Archived', 'url': '/bookmarks/archived'},
        {'name': 'Unread', 'url': '/bookmarks?unread=yes'},
        {'name': 'Untagged', 'url': '/bookmarks?q=!untagged'},
        {'name': 'Shared', 'url': '/bookmarks/shared'},
      ],
      'screenshots': [
        {
          'src': '/static/linkding-screenshot.png',
          'type': 'image/png',
          'sizes': '2158x1160',
          'form_factor': 'wide',
        },
      ],
      'share_target': {
        'action': '/bookmarks/new',
        'method': 'GET',
        'enctype': 'application/x-www-form-urlencoded',
        'params': {'url': 'url', 'text': 'url', 'title': 'title'},
      },
    };
    return c.text(pythonJson(manifest), contentType: 'application/json');
  }

  /// `/opensearch.xml`.
  Future<Response> opensearch(Request request) async {
    final c = await web.context(request);
    final base = e(c.baseUrl);
    return c.text(
      '<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/" '
      'xmlns:moz="http://www.mozilla.org/2006/browser/search/">\n'
      '    <ShortName>Linkding</ShortName>\n'
      '    <Description>Linkding</Description>\n'
      '    <InputEncoding>UTF-8</InputEncoding>\n'
      '    <Image width="16" height="16" type="image/x-icon">'
      '$base/static/favicon.ico</Image>\n'
      '    <Url type="text/html" template="$base/bookmarks?client=opensearch'
      '&amp;q={searchTerms}"/>\n'
      '</OpenSearchDescription>\n',
      contentType: 'application/opensearchdescription+xml',
    );
  }

  /// `/custom_css`: the visitor's custom CSS, cached for 30 days (pages
  /// link it with the CSS's hash).
  Future<Response> customCss(Request request) async {
    final c = await web.context(request);
    return c.text(
      c.profile.row.customCss,
      contentType: 'text/css',
      headers: {'cache-control': 'public, max-age=2592000'},
    );
  }

  /// `/toasts/acknowledge`: dismisses one of the user's toasts, then back
  /// to the page it was shown on.
  Future<Response> acknowledgeToast(Request request) async {
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
    // `request.POST["toast"]`: a missing field, or an id that is not a
    // number, is an error in linkding.
    final raw = form?['toast'];
    if (raw == null) return serverErrorPage();
    final id = pythonInt(raw);
    if (id == null) return serverErrorPage();
    final acknowledged = id < -2147483648 || id > 2147483647
        ? null
        : (await SettingsRepo(
            web.database.connection,
          ).acknowledge(id, c.user!.id)).orThrow;
    if (acknowledged == null) return notFoundPage();
    return c.redirect(safeReturnUrl(c.query['return_url'], '/bookmarks'));
  }
}

/// Python's `json.dumps` with its default separators, for the values a
/// manifest holds.
String pythonJson(Object? value) => switch (value) {
  final Map<String, Object?> map =>
    '{${map.entries.map((e) => '${jsonEncode(e.key)}: ${pythonJson(e.value)}').join(', ')}}',
  final List<Object?> list => '[${list.map(pythonJson).join(', ')}]',
  _ => jsonEncode(value),
};
