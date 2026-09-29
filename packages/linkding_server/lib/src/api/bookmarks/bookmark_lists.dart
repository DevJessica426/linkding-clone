import 'package:dust_server/server.dart';

import '../../core/profile.dart';
import '../../db/or_throw.dart';
import '../../db/repos/settings_repo.dart';
import '../../db/repos/users_repo.dart';
import '../../search/search.dart';
import 'bookmark_json.dart';
import '../errors.dart';
import '../lookups.dart';
import '../pagination.dart';
import '../view.dart';

/// `GET /api/bookmarks/`.
Future<Response> listActive(Request request) =>
    _list(request, BookmarkList.active);

/// `GET /api/bookmarks/archived/`.
Future<Response> listArchived(Request request) =>
    _list(request, BookmarkList.archived);

Future<Response> _list(Request request, BookmarkList list) async {
  final db = await apiDb(request);
  final user = await apiUserOf(request);
  final search = await BookmarkSearch.fromQuery(
    db,
    request.requestedUri.queryParameters,
    ownerId: user.id,
  );
  final matches = await BookmarkSearchQuery(db).run(
    list: list,
    search: search,
    profile: await profileOf(db, user.id),
    ownerId: user.id,
  );
  return _page(request, matches);
}

/// `GET /api/bookmarks/shared/`: shared bookmarks of users who enabled
/// sharing; without credentials, only of those who share publicly. An
/// unknown `user` shows everyone's, as in linkding.
Future<Response> listShared(Request request) async {
  final db = await apiDb(request);
  final user = (await request.extract(const Extension<ApiCaller>())).user;
  final search = await BookmarkSearch.fromQuery(
    db,
    request.requestedUri.queryParameters,
  );
  final owner = search.user.isEmpty
      ? null
      : (await UsersRepo(db).byUsername(search.user)).orThrow;
  Profile? profile;
  if (user != null) {
    profile = await profileOf(db, user.id);
  } else {
    // Anonymous visitors search with the guest profile's preferences when
    // one is configured.
    final guest = (await SettingsRepo(db).global()).orThrow?.guestProfileUserId;
    profile = guest == null ? null : await profileOf(db, guest);
  }
  final matches = await BookmarkSearchQuery(db).run(
    list: BookmarkList.shared,
    search: search,
    profile: profile,
    ownerId: owner?.id,
    publicOnly: user == null,
  );
  return _page(request, matches);
}

Future<Response> _page(Request request, List<Candidate> matches) async {
  final page = LimitOffset.fromQuery(request.requestedUri.queryParameters);
  final count = matches.length;
  final slice = count == 0 || page.offset > count
      ? const <Candidate>[]
      : matches.skip(page.offset).take(page.limit).toList();
  final url = request.requestedUri.toString();
  return apiJson({
    'count': count,
    'next': page.next(url, count),
    'previous': page.previous(url),
    'results': [for (final c in slice) bookmarkJson(request, c.row, c.tags)],
  });
}
