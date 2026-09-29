import 'package:dust_server/server.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../db/bundles_repo.dart';
import '../db/rows.dart';
import '../services/errors.dart';
import 'body.dart';
import 'bundle_fields.dart';
import 'errors.dart';
import 'lookups.dart';
import 'pagination.dart';

Map<String, Object?> _bundleJson(BundleRow row) => Bundle(
  id: row.id,
  name: row.name,
  search: row.search,
  anyTags: row.anyTags,
  allTags: row.allTags,
  excludedTags: row.excludedTags,
  filterUnread: row.filterUnread,
  filterShared: row.filterShared,
  order: row.order,
  dateCreated: row.dateCreated,
  dateModified: row.dateModified,
).toJson();

/// `GET /api/bundles/`.
Future<Response> listBundles(Request request) async {
  final page = LimitOffset.fromQuery(request.requestedUri.queryParameters);
  final user = await apiUserOf(request);
  final bundles = BundlesRepo(await apiDb(request));
  final count = (await bundles.count(user.id)).orThrow;
  final rows = count == 0 || page.offset > count
      ? const <BundleRow>[]
      : (await bundles.page(user.id, page.limit, page.offset)).orThrow;
  final url = request.requestedUri.toString();
  return apiJson({
    'count': count,
    'next': page.next(url, count),
    'previous': page.previous(url),
    'results': [for (final row in rows) _bundleJson(row)],
  });
}

/// `POST /api/bundles/`: placed last unless an `order` is given.
Future<Response> createBundle(Request request) async {
  final user = await apiUserOf(request);
  final f = bundleInput(await readRequestBody(request), partial: false);
  final repo = BundlesRepo(await apiDb(request));
  final order = f.order ?? (await repo.nextOrder(user.id)).orThrow;
  final row = (await repo.insert(
    f.name!,
    f.search ?? '',
    f.anyTags ?? '',
    f.allTags ?? '',
    f.excludedTags ?? '',
    order,
    DateTime.now().toUtc(),
    user.id,
    f.filterShared ?? 'off',
    f.filterUnread ?? 'off',
  )).orThrow;
  return apiJson(_bundleJson(row), status: 201);
}

Future<BundleRow> _ownedBundle(Request request, UserRow user) async {
  final id = await pathId(request, 'BookmarkBundle');
  final row = (await BundlesRepo(
    await apiDb(request),
  ).owned(id, user.id)).orThrow;
  if (row == null) throw ApiException.noMatch('BookmarkBundle');
  return row;
}

/// `GET /api/bundles/<id>/`.
Future<Response> retrieveBundle(Request request) async =>
    apiJson(_bundleJson(await _ownedBundle(request, await apiUserOf(request))));

/// `PUT /api/bundles/<id>/`: fields not sent keep their values.
Future<Response> replaceBundle(Request request) =>
    _update(request, partial: false);

/// `PATCH /api/bundles/<id>/`.
Future<Response> patchBundle(Request request) =>
    _update(request, partial: true);

Future<Response> _update(Request request, {required bool partial}) async {
  final row = await _ownedBundle(request, await apiUserOf(request));
  final f = bundleInput(await readRequestBody(request), partial: partial);
  final saved = (await BundlesRepo(await apiDb(request)).update(
    row.id,
    f.name ?? row.name,
    f.search ?? row.search,
    f.anyTags ?? row.anyTags,
    f.allTags ?? row.allTags,
    f.excludedTags ?? row.excludedTags,
    f.order ?? row.order,
    DateTime.now().toUtc(),
    f.filterShared ?? row.filterShared,
    f.filterUnread ?? row.filterUnread,
  )).orThrow;
  return apiJson(_bundleJson(saved));
}

/// `DELETE /api/bundles/<id>/`: renumbers the rest 0, 1, 2...
Future<Response> deleteBundle(Request request) async {
  final user = await apiUserOf(request);
  final row = await _ownedBundle(request, user);
  final repo = BundlesRepo(await apiDb(request));
  (await repo.delete(row.id, user.id)).orThrow;
  (await repo.renumber(user.id)).orThrow;
  return Response(204);
}
