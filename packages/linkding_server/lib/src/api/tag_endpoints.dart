import 'package:dust_server/server.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../db/rows.dart';
import '../db/tags_repo.dart';
import '../services/errors.dart';
import '../services/tags.dart';
import 'body.dart';
import 'errors.dart';
import 'fields.dart';
import 'lookups.dart';
import 'pagination.dart';

Map<String, Object?> _tagJson(TagRow row) =>
    Tag(id: row.id, name: row.name, dateAdded: row.dateAdded).toJson();

/// `GET /api/tags/`.
Future<Response> listTags(Request request) async {
  final page = LimitOffset.fromQuery(request.requestedUri.queryParameters);
  final user = await apiUserOf(request);
  final tags = TagsRepo(await apiDb(request));
  final count = (await tags.count(user.id)).orThrow;
  final rows = count == 0 || page.offset > count
      ? const <TagRow>[]
      : (await tags.page(user.id, page.limit, page.offset)).orThrow;
  final url = request.requestedUri.toString();
  return apiJson({
    'count': count,
    'next': page.next(url, count),
    'previous': page.previous(url),
    'results': [for (final row in rows) _tagJson(row)],
  });
}

/// `POST /api/tags/`: the existing tag when the name is taken in any case.
Future<Response> createTag(Request request) async {
  final user = await apiUserOf(request);
  final body = await readRequestBody(request);
  requireObject(body);
  final errors = FieldErrors();
  final field = fieldOf(body, 'name', partial: false);
  String? name;
  if (!field.present) {
    errors.errors['name'] = ['This field is required.'];
  } else {
    name = errors.check('name', () => text(field.value, maxLength: 64));
  }
  errors.throwIfAny();
  final tag = await getOrCreateTag(await apiDb(request), user.id, name!);
  return apiJson(_tagJson(tag), status: 201);
}

Future<TagRow> _ownedTag(Request request, UserRow user) async {
  final id = await pathId(request, 'Tag');
  final row = (await TagsRepo(await apiDb(request)).owned(id, user.id)).orThrow;
  if (row == null) throw ApiException.noMatch('Tag');
  return row;
}

/// `GET /api/tags/<id>/`.
Future<Response> retrieveTag(Request request) async =>
    apiJson(_tagJson(await _ownedTag(request, await apiUserOf(request))));

/// `DELETE /api/tags/<id>/`.
Future<Response> deleteTag(Request request) async {
  final user = await apiUserOf(request);
  final tag = await _ownedTag(request, user);
  (await TagsRepo(await apiDb(request)).delete(tag.id, user.id)).orThrow;
  return Response(204);
}
