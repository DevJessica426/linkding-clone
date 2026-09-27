import 'dart:io';

import 'package:dust_server/server.dart';

import '../compat/django.dart';
import '../compat/xml_writer.dart';
import '../core/profile.dart';
import '../db/bundles_repo.dart';
import '../db/rows.dart';
import '../db/users_repo.dart';
import '../services/errors.dart';
import '../services/search.dart';
import 'context.dart';
import 'query_params.dart';

/// The four feeds of linkding's `feeds.py`.
enum FeedKind {
  all('All bookmarks', 'All bookmarks'),
  unread('Unread bookmarks', 'All unread bookmarks'),
  shared('Shared bookmarks', 'All shared bookmarks'),
  publicShared('Public shared bookmarks', 'All public shared bookmarks');

  const FeedKind(this.title, this.description);

  final String title;
  final String description;
}

/// linkding's RSS feeds, written as Django's `Rss201rev2Feed` writes them.
/// The keyed feeds read a feed token's bookmarks; the public one reads what
/// everyone shares publicly.
final class FeedViews {
  FeedViews(this.web);

  final Web web;

  /// `/feeds/<key>/all`.
  Future<Response> all(Request request) => _keyed(request, FeedKind.all);

  /// `/feeds/<key>/unread`.
  Future<Response> unread(Request request) => _keyed(request, FeedKind.unread);

  /// `/feeds/<key>/shared`.
  Future<Response> shared(Request request) => _keyed(request, FeedKind.shared);

  /// `/feeds/shared`.
  Future<Response> publicShared(Request request) async {
    final c = await web.context(request);
    return _feed(c, FeedKind.publicShared, null);
  }

  Future<Response> _keyed(Request request, FeedKind kind) async {
    final c = await web.context(request);
    final key = await request.path<String>('key');
    final user = (await UsersRepo(web.database.connection).byFeedToken(key))
        .orThrow;
    if (user == null) return notFoundPage();
    return _feed(c, kind, (user: user, key: key));
  }

  /// `BaseBookmarksFeed.get_object`, `items` and Django's `Feed.get_feed`.
  Future<Response> _feed(
    PageContext c,
    FeedKind kind,
    ({UserRow user, String key})? token,
  ) async {
    final db = web.database.connection;
    final query = QueryParams.parse(c.request.requestedUri.query);

    // `access.bundle_read`, by the signed-in visitor: a visitor who is not
    // signed in makes the lookup fail with an error.
    BundleRow? bundle;
    final bundleId = query['bundle'] ?? '';
    if (bundleId.isNotEmpty) {
      final visitor = c.user;
      if (visitor == null) return serverErrorPage();
      final id = pythonInt(bundleId);
      if (id == null || id < -2147483648 || id > 2147483647) {
        return notFoundPage();
      }
      bundle = (await BundlesRepo(db).owned(id, visitor.id)).orThrow;
      if (bundle == null) return notFoundPage();
    }

    final search = BookmarkSearch(
      q: query['q'] ?? '',
      user: query['user'] ?? '',
      bundle: bundle,
      unread: _orDefault(query['unread'], 'off'),
      shared: _orDefault(query['shared'], 'off'),
    );

    // `items`: the first `limit` bookmarks, 100 unless asked otherwise, and
    // all of them for an empty `limit`.
    final rawLimit = query['limit'];
    int? limit = 100;
    if (rawLimit != null) {
      limit = rawLimit.isEmpty ? null : pythonInt(rawLimit);
      // `int()` fails, and a negative slice is refused.
      if (rawLimit.isNotEmpty && (limit == null || limit < 0)) {
        return serverErrorPage();
      }
    }

    final items = await _items(kind, search, token?.user);
    final shown = limit == null || items.length <= limit
        ? items
        : items.sublist(0, limit);

    final base = c.baseUrl;
    final link = switch (kind) {
      FeedKind.publicShared => '/feeds/shared',
      _ => '/feeds/${token!.key}/${kind.name}',
    };
    final String body;
    try {
      body = _write(
        kind,
        link: iriToUri(_addDomain(base, link)),
        feedUrl: iriToUri(_addDomain(base, c.path)),
        items: shown,
        base: base,
      );
    } on UnserializableContentError {
      return serverErrorPage();
    }
    final latest = _latest(shown);
    return c.text(
      body,
      contentType: 'application/rss+xml; charset=utf-8',
      headers: {HttpHeaders.lastModifiedHeader: HttpDate.format(latest)},
    );
  }

  /// The query set of each feed.
  Future<List<Candidate>> _items(
    FeedKind kind,
    BookmarkSearch search,
    UserRow? tokenUser,
  ) async {
    final db = web.database.connection;
    final searches = BookmarkSearchQuery(db);
    Future<Profile> profileOf(int userId) async => Profile(
      (await UsersRepo(db).profile(userId)).orThrow ?? standardProfile,
    );

    switch (kind) {
      case FeedKind.all || FeedKind.unread:
        final user = tokenUser!;
        final items = await searches.run(
          list: BookmarkList.active,
          search: search,
          profile: await profileOf(user.id),
          ownerId: user.id,
        );
        return kind == FeedKind.unread
            ? [
                for (final item in items)
                  if (item.row.unread) item,
              ]
            : items;
      case FeedKind.shared || FeedKind.publicShared:
        // `resolve_user`: an unknown user name means no bookmarks at all.
        int? ownerId;
        if (search.user.isNotEmpty) {
          final owner = (await UsersRepo(db).byUsername(search.user)).orThrow;
          if (owner == null) return const [];
          ownerId = owner.id;
        }
        final publicOnly = kind == FeedKind.publicShared;
        return searches.run(
          list: BookmarkList.shared,
          search: search,
          profile: publicOnly
              ? Profile(standardProfile)
              : await profileOf(tokenUser!.id),
          ownerId: ownerId,
          publicOnly: publicOnly,
        );
    }
  }

  /// `latest_post_date`: the newest item, or now for an empty feed.
  static DateTime _latest(List<Candidate> items) {
    DateTime? latest;
    for (final item in items) {
      final added = item.row.dateAdded;
      if (latest == null || added.isAfter(latest)) latest = added;
    }
    return latest ?? DateTime.now().toUtc();
  }

  /// `Rss201rev2Feed.write`.
  static String _write(
    FeedKind kind, {
    required String link,
    required String feedUrl,
    required List<Candidate> items,
    required String base,
  }) {
    final xml = SimplerXmlGenerator()
      ..startDocument()
      ..startElement('rss', {
        'version': '2.0',
        'xmlns:atom': 'http://www.w3.org/2005/Atom',
      })
      ..startElement('channel')
      ..addQuickElement('title', kind.title)
      ..addQuickElement('link', link)
      ..addQuickElement('description', kind.description)
      ..addQuickElement('atom:link', null, {'rel': 'self', 'href': feedUrl})
      // Django's `get_language()`: without translations, English.
      ..addQuickElement('language', 'en')
      ..addQuickElement('lastBuildDate', rfc2822Date(_latest(items)));
    for (final item in items) {
      final b = item.row;
      // `unique_id` is the link before `add_item` passes it through
      // `iri_to_uri`.
      final guid = _addDomain(base, b.url);
      xml
        ..startElement('item')
        ..addQuickElement('title', _sanitize(b.title.isEmpty ? b.url : b.title))
        ..addQuickElement('link', iriToUri(guid))
        ..addQuickElement('description', _sanitize(b.description))
        ..addQuickElement('pubDate', rfc2822Date(b.dateAdded))
        ..addQuickElement('guid', guid);
      for (final tag in [...item.tags]..sort(_compareCodePoints)) {
        xml.addQuickElement('category', tag);
      }
      xml.endElement('item');
    }
    xml
      ..endElement('channel')
      ..endElement('rss');
    return xml.toString();
  }
}

String _orDefault(String? value, String fallback) =>
    value == null || value.isEmpty ? fallback : value;

/// Django's `add_domain`: a path gets the site's scheme and host, a
/// network-path reference gets `http:`, and absolute `http`, `https` and
/// `mailto` URLs are kept as they are.
String _addDomain(String base, String url) {
  if (url.startsWith('//')) return 'http:$url';
  if (url.startsWith('http://') ||
      url.startsWith('https://') ||
      url.startsWith('mailto:')) {
    return url;
  }
  return iriToUri('$base$url');
}

/// linkding's `sanitize`: control and other invisible characters (Unicode
/// category C) removed, except line breaks and tabs.
final _invisible = RegExp(r'[^\P{C}\n\r\t]', unicode: true);
String _sanitize(String text) => text.replaceAll(_invisible, '');

/// Python's string order, by code point.
int _compareCodePoints(String a, String b) {
  final x = a.runes.toList();
  final y = b.runes.toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i] - y[i];
  }
  return x.length - y.length;
}
