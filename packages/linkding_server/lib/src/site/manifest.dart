import 'dart:convert';

import 'package:dust_server/server.dart';

import '../pages/session/visitor.dart';

/// `/manifest.json`, written as Django's `JsonResponse` writes linkding's
/// web app manifest; the background follows the visitor's theme.
Future<Response> manifest(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final dark = visitor.profile.row.theme == 'dark';
  Map<String, String> icon(String src, String type, String sizes, String p) => {
    'src': '/static/$src',
    'type': type,
    'sizes': sizes,
    'purpose': p,
  };
  final manifest = {
    'short_name': 'linkding',
    'name': 'linkding',
    'description': 'Self-hosted bookmark service',
    'start_url': 'bookmarks',
    'display': 'standalone',
    'scope': '/',
    'theme_color': '#5856e0',
    'background_color': dark ? '#161822' : '#ffffff',
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
  return Response.ok(
    pythonJson(manifest),
    headers: {'content-type': 'application/json'},
  );
}

/// Python's `json.dumps` with its default separators, for the values a
/// manifest holds.
String pythonJson(Object? value) => switch (value) {
  final Map<String, Object?> map =>
    '{${map.entries.map((e) => '${jsonEncode(e.key)}: ${pythonJson(e.value)}').join(', ')}}',
  final List<Object?> list => '[${list.map(pythonJson).join(', ')}]',
  _ => jsonEncode(value),
};
