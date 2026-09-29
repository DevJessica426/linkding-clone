import 'package:dust_server/server.dart';

import '../../compat/form_data.dart';
import '../../config.dart';
import '../../core/urls.dart';
import '../../db/repos/bookmarks_repo.dart';
import '../../db/database.dart';
import '../../pages/support/html.dart' show q;
import '../../pages/support/render.dart';
import '../../pages/support/return_url.dart';
import '../../pages/session/visitor.dart';
import '../service/bookmark_service.dart';
import '../../db/or_throw.dart';
import 'bookmark_form.dart';
import 'form_values.dart';

/// `/bookmarks/new`: prefilled from the query string, as the bookmarklet
/// and browser extension open it.
Future<Response> newBookmark(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final profile = visitor.profile.row;
  final BookmarkForm form;
  if (request.method == 'POST') {
    form = await _submitted(request);
    form.hasNotes = form.cleaned['notes']!.isNotEmpty;
    if (form.isValid) {
      await (await request.state<BookmarkService>()).create(
        form.draft(),
        form.tagString,
        visitor.signedIn.id,
        visitor.profile,
        scrape: false,
      );
      final next = form.isAutoClose ? '/bookmarks/close' : '/bookmarks';
      return Redirect.found(next).intoResponse();
    }
  } else {
    final query = visitor.query;
    form = BookmarkForm(
      url: query['url'],
      title: query['title'],
      description: query['description'],
      notes: query['notes'],
      tagString: query['tags'],
      autoClose: query.containsKey('auto_close') ? 'True' : 'False',
      unread: profile.defaultMarkUnread,
      shared: profile.defaultMarkShared,
      hasNotes: (query['notes'] ?? '').isNotEmpty,
    );
  }
  return _page(
    request,
    visitor,
    form,
    'New bookmark',
    '/bookmarks/new',
    '/bookmarks',
    0,
  );
}

/// `/bookmarks/<id>/edit`, back to `return_url` when saved.
Future<Result<Response, Rejection>> editBookmark(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final user = visitor.signedIn;
  final repo = BookmarksRepo(
    (await request.state<LinkdingDatabase>()).connection,
  );
  final id = int.tryParse(await request.path<String>('id'));
  final bookmark = id == null || id > 2147483647
      ? null
      : (await repo.owned(id, user.id)).orThrow;
  if (bookmark == null) {
    return const Err(Rejection.notFound('No Bookmark matches'));
  }
  final returnUrl = safeReturnUrl(visitor.query['return_url'], '/bookmarks');
  final bookmarks = await request.state<BookmarkService>();

  final BookmarkForm form;
  if (request.method == 'POST') {
    form = await _submitted(request);
    // A model form's initial values are the saved bookmark's.
    form.hasNotes =
        bookmark.notes.isNotEmpty || form.cleaned['notes']!.isNotEmpty;
    if (form.errors['url']!.isEmpty &&
        (await repo.duplicate(
          user.id,
          normalizeUrl(form.url),
          form.url!,
          bookmark.id,
        )).orThrow) {
      form.errors['url']!.add('A bookmark with this URL already exists.');
    }
    if (form.isValid) {
      await bookmarks.update(
        bookmark.id,
        form.draft(
          isArchived: bookmark.isArchived,
          dateAdded: bookmark.dateAdded,
        ),
        form.tagString,
        user.id,
        visitor.profile,
      );
      return Ok(Redirect.found(returnUrl).intoResponse());
    }
  } else {
    final tags = await bookmarks.tagNames([bookmark.id]);
    form = BookmarkForm(
      url: bookmark.url,
      title: bookmark.title,
      description: bookmark.description,
      notes: bookmark.notes,
      tagString: (tags[bookmark.id] ?? const []).join(' '),
      unread: bookmark.unread,
      shared: bookmark.shared,
      hasNotes: bookmark.notes.isNotEmpty,
    );
  }
  final action = '/bookmarks/${bookmark.id}/edit?return_url=${q(returnUrl)}';
  return Ok(
    await _page(
      request,
      visitor,
      form,
      'Edit bookmark',
      action,
      returnUrl,
      bookmark.id,
    ),
  );
}

/// `/bookmarks/close`, where a popup goes after saving.
Future<Response> closeBookmark(Request request) async => renderPage(
  await request.state<TemplateEngine>(),
  await request.extract(const Extension<Visitor>()),
  title: 'Linkding',
  template: 'bookmarks/close',
);

/// The posted form, checked.
Future<BookmarkForm> _submitted(Request request) async {
  final config = await request.state<ServerConfig>();
  return BookmarkForm.bound(await request.extract(const PostedForm()))
    ..validate(checkUrl: !config.disableUrlValidation);
}

Future<Response> _page(
  Request request,
  Visitor visitor,
  BookmarkForm form,
  String heading,
  String action,
  String returnUrl,
  int bookmarkId,
) async => renderPage(
  await request.state<TemplateEngine>(),
  visitor,
  title: '$heading - Linkding',
  template: 'bookmarks/form',
  values: formValues(
    visitor,
    form,
    heading: heading,
    action: action,
    returnUrl: returnUrl,
    bookmarkId: bookmarkId,
  ),
  status: form.isBound ? 422 : 200,
);
