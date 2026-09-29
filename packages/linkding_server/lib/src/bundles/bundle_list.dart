import 'package:dust_server/server.dart';

import '../compat/form_data.dart';
import '../db/bundles_repo.dart';
import '../db/database.dart';
import '../db/rows.dart';
import '../pages/render.dart';
import '../pages/session_data.dart';
import '../pages/visitor.dart';
import '../services/errors.dart';

/// `/bundles`: the user's bundles, in their order.
Future<Response> bundleIndex(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final repo = await _repo(request);
  final bundles = (await repo.all(visitor.signedIn.id)).orThrow;
  final messages = await (await SessionData.of(request)).takeMessages();
  return renderPage(
    await request.state<TemplateEngine>(),
    visitor,
    title: 'Bundles - Linkding',
    template: 'bundles/index',
    values: {
      ...messageValues(messages),
      'hasBundles': bundles.isNotEmpty,
      'bundles': [
        for (final bundle in bundles) {'id': bundle.id, 'name': bundle.name},
      ],
    },
  );
}

/// `/bundles/action`: removing a bundle, or moving one to a new place.
Future<Result<Response, Rejection>> bundleAction(Request request) async {
  final user = (await request.extract(const Extension<Visitor>())).signedIn;
  final form = await request.extract(const PostedForm());
  final repo = await _repo(request);
  if (form.has('remove_bundle')) {
    final bundle = await ownedBundle(repo, form['remove_bundle'], user.id);
    if (bundle == null) return const Err(_missing);
    (await repo.delete(bundle.id, user.id)).orThrow;
    (await repo.renumber(user.id)).orThrow;
    await (await SessionData.of(request))
        .addMessage("Bundle '${bundle.name}' removed successfully.");
  } else if (form.has('move_bundle')) {
    final bundle = await ownedBundle(repo, form['move_bundle'], user.id);
    if (bundle == null) return const Err(_missing);
    final position = int.tryParse(form['move_position']?.trim() ?? '');
    if (position == null) {
      return Ok(
        Response(400, headers: {'content-type': 'text/html; charset=utf-8'}),
      );
    }
    await _move(repo, bundle, position, user.id);
  }
  return Ok(Redirect.found('/bundles').intoResponse());
}

const _missing = Rejection.notFound('No BookmarkBundle matches');

/// linkding's `access.bundle_write`: the user's bundle with the id in [id].
Future<BundleRow?> ownedBundle(BundlesRepo repo, String? id, int owner) async {
  final bundleId = int.tryParse(id?.trim() ?? '');
  if (bundleId == null || bundleId > 2147483647) return null;
  return (await repo.owned(bundleId, owner)).orThrow;
}

/// `move_bundle`: takes the bundle out and puts it back at [position], as
/// Python's `list.insert` places it, then numbers the bundles in order.
Future<void> _move(
  BundlesRepo repo,
  BundleRow bundle,
  int position,
  int ownerId,
) async {
  final bundles = (await repo.all(ownerId)).orThrow;
  final current = bundles.indexWhere((b) => b.id == bundle.id);
  if (position == current) return;
  final ordered = [...bundles]..removeAt(current);
  var at = position < 0 ? ordered.length + position : position;
  at = at.clamp(0, ordered.length);
  ordered.insert(at, bundles[current]);
  for (final (index, b) in ordered.indexed) {
    (await repo.setOrder(b.id, index)).orThrow;
  }
}

Future<BundlesRepo> _repo(Request request) async =>
    BundlesRepo((await request.state<LinkdingDatabase>()).connection);
