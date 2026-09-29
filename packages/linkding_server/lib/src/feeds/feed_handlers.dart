import 'dart:io';

import 'package:dust_server/server.dart';

import '../compat/django.dart';
import '../compat/xml_writer.dart';
import '../db/bundles_repo.dart';
import '../db/database.dart';
import '../db/rows.dart';
import '../db/users_repo.dart';
import '../pages/query_params.dart';
import '../pages/visitor.dart';
import '../services/errors.dart';
import '../services/search.dart';
import 'feed_items.dart';
import 'rss.dart';

/// linkding's RSS feeds: a feed token's bookmarks, and the public ones.
Router feedRoutes() => Router()
  ..route('/feeds/shared', any(publicSharedFeed))
  ..route('/feeds/{key}/all', any((r) => _keyed(r, FeedKind.all)))
  ..route('/feeds/{key}/unread', any((r) => _keyed(r, FeedKind.unread)))
  ..route('/feeds/{key}/shared', any((r) => _keyed(r, FeedKind.shared)));

/// `/feeds/shared`: every publicly shared bookmark.
Future<Result<Response, Rejection>> publicSharedFeed(Request request) =>
    _feed(request, FeedKind.publicShared, null);

const _missing = Rejection.notFound('Feed object does not exist.');

/// Where linkding fails with an exception.
const _failure = Rejection.internal();

Future<Result<Response, Rejection>> _keyed(
  Request request,
  FeedKind kind,
) async {
  final db = (await request.state<LinkdingDatabase>()).connection;
  final key = await request.path<String>('key');
  final user = (await UsersRepo(db).byFeedToken(key)).orThrow;
  if (user == null) return const Err(_missing);
  return _feed(request, kind, (user: user, key: key));
}

/// `BaseBookmarksFeed.get_object`, `items` and Django's `Feed.get_feed`.
Future<Result<Response, Rejection>> _feed(
  Request request,
  FeedKind kind,
  ({UserRow user, String key})? token,
) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final db = (await request.state<LinkdingDatabase>()).connection;
  final query = QueryParams.parse(request.requestedUri.query);

  // `access.bundle_read`, by the signed-in visitor: a visitor who is not
  // signed in makes the lookup fail with an error.
  BundleRow? bundle;
  final bundleId = query['bundle'] ?? '';
  if (bundleId.isNotEmpty) {
    final user = visitor.user;
    if (user == null) return const Err(_failure);
    final id = pythonInt(bundleId);
    if (id == null || id < -2147483648 || id > 2147483647) {
      return const Err(Rejection.notFound('Bundle does not exist'));
    }
    bundle = (await BundlesRepo(db).owned(id, user.id)).orThrow;
    if (bundle == null) {
      return const Err(Rejection.notFound('Bundle does not exist'));
    }
  }
  final search = BookmarkSearch(
    q: query['q'] ?? '',
    user: query['user'] ?? '',
    bundle: bundle,
    unread: _orDefault(query['unread'], 'off'),
    shared: _orDefault(query['shared'], 'off'),
  );

  // `items`: the first `limit` bookmarks, 100 unless asked otherwise, and
  // all of them for an empty `limit`. `int()` failing and a negative slice
  // are errors.
  final rawLimit = query['limit'];
  final limit = rawLimit == null
      ? 100
      : rawLimit.isEmpty
      ? null
      : pythonInt(rawLimit);
  if (rawLimit != null && rawLimit.isNotEmpty && (limit == null || limit < 0)) {
    return const Err(_failure);
  }
  final items = await feedItems(db, kind, search, token?.user);
  final shown = limit == null || items.length <= limit
      ? items
      : items.sublist(0, limit);

  final base = visitor.baseUrl;
  final link = kind == FeedKind.publicShared
      ? '/feeds/shared'
      : '/feeds/${token!.key}/${kind.name}';
  final String body;
  try {
    body = writeRss(
      kind,
      link: iriToUri(addDomain(base, link)),
      feedUrl: iriToUri(addDomain(base, visitor.path)),
      items: shown,
      base: base,
    );
  } on UnserializableContentError {
    return const Err(_failure);
  }
  return Ok(
    Response(
      200,
      body: body,
      headers: {
        HttpHeaders.contentTypeHeader: 'application/rss+xml; charset=utf-8',
        HttpHeaders.lastModifiedHeader: HttpDate.format(latestPostDate(shown)),
      },
    ),
  );
}

String _orDefault(String? value, String fallback) =>
    value == null || value.isEmpty ? fallback : value;
