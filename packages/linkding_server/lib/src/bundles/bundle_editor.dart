import 'package:dust_server/server.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../compat/form_data.dart';
import '../db/repos/bundles_repo.dart';
import '../db/database.dart';
import '../db/or_throw.dart';
import '../db/rows/rows.dart';
import '../pages/support/render.dart';
import '../pages/session/session_data.dart';
import '../pages/session/visitor.dart';
import 'bundle_fields.dart';
import 'bundle_form_values.dart';
import 'bundle_list.dart';
import 'bundle_preview.dart';

/// `/bundles/new`, prefilled from a search with `?q=`.
Future<Response> newBundle(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final initial = <String, String>{};
  final q = visitor.query['q'];
  if (request.method != 'POST' && q != null && q.isNotEmpty) {
    final parsed = LegacyQuery.parse(q);
    if (parsed.searchTerms.isNotEmpty) {
      initial['search'] = parsed.searchTerms.join(' ');
    }
    if (parsed.tagNames.isNotEmpty) {
      initial['all_tags'] = parsed.tagNames.join(' ');
    }
  }
  return _editor(request, null, initial);
}

/// `/bundles/<id>/edit`.
Future<Result<Response, Rejection>> editBundle(Request request) async {
  final user = (await request.extract(const Extension<Visitor>())).signedIn;
  final repo = BundlesRepo(
    (await request.state<LinkdingDatabase>()).connection,
  );
  final bundle = await ownedBundle(
    repo,
    await request.path<String>('id'),
    user.id,
  );
  if (bundle == null) {
    return const Err(Rejection.notFound('No BookmarkBundle matches'));
  }
  return Ok(await _editor(request, bundle, const {}));
}

/// linkding's `_handle_edit`: the form, saved when valid, with a preview of
/// what the bundle matches.
Future<Response> _editor(
  Request request,
  BundleRow? bundle,
  Map<String, String> initial,
) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final isPost = request.method == 'POST';
  final posted = {
    for (final MapEntry(:key, :value) in (await request.extract(
      const PostedForm(),
    )).fields.entries)
      key: value.last,
  };
  final BundleFields fields;
  final errors = <String, List<String>>{};
  if (isPost) {
    fields = BundleFields.fromData(posted, bundle);
    errors.addAll(fields.validate());
    if (errors.values.every((e) => e.isEmpty)) {
      await _save(request, fields, bundle, visitor.signedIn.id);
      await (await SessionData.of(request))
          .addMessage('Bundle saved successfully.');
      return Redirect.found('/bundles').intoResponse();
    }
  } else {
    fields = BundleFields.initial(bundle, initial);
  }

  // The preview shows the saved bundle while nothing has been typed, and
  // otherwise what the form holds. A new form, not bound to the bundle,
  // so a filter left out is "off".
  final previewed = !isPost && bundle != null
      ? bundle
      : BundleFields.fromData(
          isPost ? posted : {...visitor.query, ...initial},
          null,
        ).toBundle(visitor.signedIn.id);
  final heading = bundle == null ? 'New bundle' : 'Edit bundle';
  final messages = await (await SessionData.of(request)).takeMessages();
  return renderPage(
    await request.state<TemplateEngine>(),
    visitor,
    title: '$heading - Linkding',
    template: 'bundles/editor',
    values: {
      ...messageValues(messages),
      ...bundleFormValues(fields, errors),
      'heading': heading,
      'action': bundle == null ? '/bundles/new' : '/bundles/${bundle.id}/edit',
      'preview': await renderPreview(request, previewed),
    },
    status: isPost ? 422 : 200,
  );
}

Future<void> _save(
  Request request,
  BundleFields v,
  BundleRow? bundle,
  int ownerId,
) async {
  final repo = BundlesRepo(
    (await request.state<LinkdingDatabase>()).connection,
  );
  final now = DateTime.now().toUtc();
  if (bundle == null) {
    (await repo.insert(
      v.name,
      v.search,
      v.anyTags,
      v.allTags,
      v.excludedTags,
      (await repo.nextOrder(ownerId)).orThrow,
      now,
      ownerId,
      v.filterShared,
      v.filterUnread,
    )).orThrow;
  } else {
    (await repo.update(
      bundle.id,
      v.name,
      v.search,
      v.anyTags,
      v.allTags,
      v.excludedTags,
      bundle.order,
      now,
      v.filterShared,
      v.filterUnread,
    )).orThrow;
  }
}
