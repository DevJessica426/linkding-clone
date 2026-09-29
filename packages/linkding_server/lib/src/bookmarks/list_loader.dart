import 'package:dust_dart/db.dart';
import 'package:dust_server/server.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../config.dart';
import '../core/profile.dart';
import '../db/bundles_repo.dart';
import '../db/database.dart';
import '../db/rows.dart';
import '../db/tags_repo.dart';
import '../db/users_repo.dart';
import '../pages/paginator.dart';
import '../pages/query_params.dart';
import '../pages/visitor.dart';
import '../services/errors.dart';
import '../services/search.dart';
import 'details_loader.dart';
import 'list_kind.dart';
import 'list_links.dart';
import 'list_page.dart';
import 'tag_cloud.dart';

/// Everything one list page shows, as linkding's `index`, `archived` and
/// `shared` views gather it from the request's query string.
Future<ListPage> loadListPage(Request request, ListKind kind) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final db = (await request.state<LinkdingDatabase>()).connection;
  final config = await request.state<ServerConfig>();
  final query = QueryParams.parse(request.requestedUri.query);
  final profile = visitor.profile;
  final userId = visitor.user?.id;
  final publicOnly = !visitor.isAuthenticated;
  final search = await BookmarkSearch.fromQuery(
    db,
    query.last,
    ownerId: userId,
    preferences: profile.searchPreferences,
  );

  var ownerId = userId;
  if (kind == ListKind.shared) {
    ownerId = search.user.isEmpty
        ? null
        : (await UsersRepo(db).byUsername(search.user)).orThrow?.id;
  }
  final candidates = await searchList(
    db,
    kind,
    search,
    profile,
    ownerId: ownerId,
    publicOnly: publicOnly,
  );
  final page = Page.of(candidates, profile.row.itemsPerPage, query['page']);

  final owners = {
    for (final u in (await UsersRepo(db).names([
      ...{for (final item in page.items) item.row.ownerId},
    ])).orThrow)
      u.id: u.username,
  };

  final tagNames = extractTagNamesFromQuery(search.q, laxTags: profile.laxTags);
  final selectedTags = tagNames.isEmpty
      ? const <TagRow>[]
      : kind == ListKind.shared
      ? (await TagsRepo(db).sharedNamed(ownerId, publicOnly, tagNames)).orThrow
      : (await TagsRepo(db).withNames(userId!, tagNames)).orThrow;
  final tagCloud = TagCloud.of(profile.row.tagGrouping, [
    for (final candidate in candidates) ...candidate.tagRows,
  ], selectedTags);

  List<BundleRow>? bundles;
  List<String>? users;
  if (kind == ListKind.shared) {
    final everyone = ownerId == null
        ? candidates
        : await searchList(db, kind, search, profile, publicOnly: publicOnly);
    final names = (await UsersRepo(db).names([
      ...{for (final c in everyone) c.row.ownerId},
    ])).orThrow;
    users = [for (final u in names) u.username]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  } else {
    bundles = (await BundlesRepo(db).all(userId!)).orThrow;
  }

  return ListPage(
    kind: kind,
    links: ListLinks(kind, query, profile),
    query: query,
    search: search,
    page: page,
    owners: owners,
    tagCloud: tagCloud,
    bundles: bundles,
    selectedBundleId: int.tryParse(query['bundle'] ?? ''),
    users: users,
    details: await loadDetails(
      db,
      visitor,
      query['details'],
      uploadsEnabled: !config.disableAssetUpload,
    ),
  );
}

/// The bookmarks of [kind] matching [search]: the owner's, or on the
/// shared list, everyone's shared ones ([ownerId]'s when a user is picked).
Future<List<Candidate>> searchList(
  Executor db,
  ListKind kind,
  BookmarkSearch search,
  Profile profile, {
  int? ownerId,
  bool publicOnly = false,
}) => BookmarkSearchQuery(db).run(
  list: kind.list,
  search: search,
  profile: profile,
  ownerId: ownerId,
  publicOnly: publicOnly,
);
