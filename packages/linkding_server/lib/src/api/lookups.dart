import 'package:dust_dart/db.dart';
import 'package:dust_server/server.dart';

import '../core/profile.dart';
import '../db/database.dart';
import '../db/or_throw.dart';
import '../db/repos/profiles_repo.dart';
import '../db/rows/rows.dart';
import 'errors.dart';
import 'view.dart';

/// The database, for an API handler.
Future<Executor> apiDb(Request request) async =>
    (await request.state<LinkdingDatabase>()).connection;

/// The caller of an endpoint that needs one.
Future<UserRow> apiUserOf(Request request) => request.extract(const ApiUser());

/// The saved preferences of [userId].
Future<Profile> profileOf(Executor db, int userId) async =>
    Profile((await ProfilesRepo(db).profile(userId)).orThrow!);

/// The id in the path: 404 "Not found." when it is not a number, and "No
/// [model] matches" when it cannot name a row.
Future<int> pathId(Request request, String model) async {
  final id = int.tryParse(await request.path<String>('id'));
  if (id == null) throw ApiException.notFound;
  if (id < -2147483648 || id > 2147483647) throw ApiException.noMatch(model);
  return id;
}

/// `request.build_absolute_uri(path)`.
String absoluteUrl(Request request, String path) {
  final uri = request.requestedUri;
  return '${uri.scheme}://${request.headers['host'] ?? uri.authority}$path';
}
