import 'dart:convert';
import 'dart:js_interop';

import 'package:linkding_shared/linkding_shared.dart';
import 'package:web/web.dart' as web;

/// The two API calls the pages make, with the signed-in session: linkding's
/// `api.js`. Requests are built as linkding builds them; answers are read
/// with the shared models.
final class Api {
  Api(this.baseUrl);

  /// `<html data-api-base-url>`, `/api/` on linkding's pages.
  factory Api.ofPage() => Api(
    web.document.documentElement?.getAttribute('data-api-base-url') ?? '',
  );

  final String baseUrl;

  /// Bookmarks matching [search] (empty values left out), from the list at
  /// [path] (`''`, `/archived` or `/shared`).
  Future<List<Bookmark>> listBookmarks(
    Map<String, String?> search, {
    int limit = 100,
    int offset = 0,
    String path = '',
  }) async {
    final query = [
      'limit=$limit',
      'offset=$offset',
      for (final MapEntry(:key, :value) in search.entries)
        if (value != null && value.isNotEmpty)
          '$key=${Uri.encodeComponent(value)}',
    ].join('&');
    final json = await _get('${baseUrl}bookmarks$path/?$query');
    return BookmarkPage.fromJson(json).results;
  }

  Future<List<Tag>> getTags({int limit = 100, int offset = 0}) async {
    final json = await _get('${baseUrl}tags/?limit=$limit&offset=$offset');
    return TagPage.fromJson(json).results;
  }

  static Future<Map<String, Object?>> _get(String url) async {
    final response = await web.window.fetch(url.toJS).toDart;
    final text = (await response.text().toDart).toDart;
    return jsonDecode(text) as Map<String, Object?>;
  }
}

final api = Api.ofPage();
