import 'package:dust_server/server.dart';

import '../compat/form_data.dart';
import '../db/database.dart';
import '../db/or_throw.dart';
import '../db/repos/tags_repo.dart';
import '../pages/support/query.dart';
import '../pages/support/query_params.dart';
import '../pages/support/render.dart';
import '../pages/session/session_data.dart';
import '../pages/support/turbo.dart';
import '../pages/session/visitor.dart';
import '../pages/support/widgets.dart';
import 'tag_forms.dart';

/// linkding's tag dialogs, each a Turbo frame; a form with errors comes
/// back as a Turbo Stream that replaces the dialog.
/// What every dialog handler reads first.
typedef TagContext = (Visitor, TemplateEngine, TagsRepo);

Future<TagContext> tagContext(Request request) async => (
  await request.extract(const Extension<Visitor>()),
  await request.state<TemplateEngine>(),
  TagsRepo((await request.state<LinkdingDatabase>()).connection),
);

/// `/tags/new`.
Future<Response> tagCreate(Request request) async {
  final (visitor, engine, tags) = await tagContext(request);
  final dialog = _NameDialog(engine, visitor, '/tags/new', '_top', '/tags');
  if (request.method != 'POST') return htmlResponse(dialog.render(null, []));
  final form = await request.extract(const PostedForm());
  final user = visitor.signedIn;
  final (name, errors) = await cleanTagName(tags, form['name'], user.id);
  if (errors.isNotEmpty) {
    return replaceTagDialog(dialog.render(form['name'], errors));
  }
  (await tags.insert(name, DateTime.now().toUtc(), user.id)).orThrow;
  await (await SessionData.of(request))
      .addMessage('Tag "$name" created successfully.');
  return Redirect.found('/tags').intoResponse();
}

/// `/tags/<id>/edit`: renaming a tag, keeping the page's filters.
Future<Result<Response, Rejection>> tagEdit(Request request) async {
  final (visitor, engine, tags) = await tagContext(request);
  final user = visitor.signedIn;
  final tag = await ownedTag(tags, await request.path<String>('id'), user.id);
  if (tag == null) return const Err(Rejection.notFound('No Tag matches'));
  final query = QueryParams.parse(request.requestedUri.query).encode();
  final dialog = _NameDialog(
    engine,
    visitor,
    '/tags/${tag.id}/edit?$query',
    'tag-main',
    '/tags?$query',
    title: 'Edit Tag',
  );
  if (request.method != 'POST') {
    return Ok(htmlResponse(dialog.render(tag.name, [])));
  }
  final form = await request.extract(const PostedForm());
  final (name, errors) = await cleanTagName(
    tags,
    form['name'],
    user.id,
    except: tag.id,
  );
  if (errors.isNotEmpty) {
    return Ok(replaceTagDialog(dialog.render(form['name'], errors)));
  }
  (await tags.rename(tag.id, user.id, name)).orThrow;
  return Ok(Redirect.found(withQuery('/tags', request)).intoResponse());
}

/// `tags/new.html` and `tags/edit.html`: the name, in a dialog.
final class _NameDialog {
  _NameDialog(
    this.engine,
    this.visitor,
    this.action,
    this.target,
    this.closeUrl, {
    this.title = 'Create Tag',
  });

  final TemplateEngine engine;
  final Visitor visitor;
  final String action;
  final String target;
  final String closeUrl;
  final String title;

  String render(String? name, List<String> errors) =>
      tagDialog(engine, visitor, {
        'action': action,
        'target': target,
        'closeUrl': closeUrl,
        'title': title,
        'modalClass': 'modal tag-edit-modal active',
        'submit': 'Save',
        'body': engine.render('tags/name-field', {
          'widget': inputField(
            'text',
            'name',
            name,
            fieldAttributes(
              'name',
              widget: const {'class': 'form-input', 'autocomplete': 'off'},
              required: true,
              hasHelp: true,
              errors: errors,
              extra: const {'autofocus': true},
            ),
          ),
          'errors': errorList('name', errors),
        }),
      });
}

/// `tags/dialog.html` with [values].
String tagDialog(
  TemplateEngine engine,
  Visitor visitor,
  Map<String, Object?> values,
) => engine.render('tags/dialog', {...commonValues(visitor), ...values});

/// `turbo.stream(turbo.replace("tag-modal", ..., method="morph"))`.
Response replaceTagDialog(String dialog) =>
    turboStream([turboReplace('tag-modal', dialog, method: 'morph')]);
