import 'package:dust_dart/db.dart';
import 'package:dust_server/server.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../auth/sessions.dart';
import '../compat/form_data.dart';
import '../compat/pyurl.dart';
import '../config.dart';
import '../db/rows.dart';
import '../db/tags_repo.dart';
import '../services/errors.dart';
import 'bookmark_list.dart';
import 'context.dart';
import 'format.dart';
import 'forms.dart';
import 'html.dart';
import 'layout.dart';
import 'query_params.dart';

/// linkding's `views/tags.py`: the tags page, and the dialogs to create,
/// rename and merge tags. The dialogs are Turbo frames; a form with errors
/// comes back as a Turbo Stream that replaces the dialog.
final class TagViews {
  TagViews(this.web);

  final Web web;

  Executor get _db => web.database.connection;

  /// `/tags`: search, filter, sort and page through the tags, or remove one.
  Future<Response> index(Request request) async {
    final (c, form, failure) = await _begin(request);
    if (failure != null) return failure;
    final user = c.user!;

    if (form != null && form.has('delete_tag')) {
      final tag = await _owned(form['delete_tag'], user.id);
      if (tag == null) return notFoundPage();
      (await TagsRepo(_db).delete(tag.id, user.id)).orThrow;
      return c.redirect(_withQuery('/tags', c));
    }

    final query = c.query;
    final search = (query['search'] ?? '').trim();
    final unusedOnly = query['unused'] == 'true';
    final sort = query['sort'] ?? 'name-asc';
    final total = (await TagsRepo(_db).count(user.id)).orThrow;
    final rows = (await TagsRepo(_db).listing(
      user.id,
      search.isEmpty ? '' : '%${_escapeLike(search)}%',
      unusedOnly,
      sort,
    )).orThrow;
    final page = Page.of(rows, 50, query['page']);
    final messages = await web.takeMessages(c);
    return c.html(
      layout(
        c,
        title: 'Tags - Linkding',
        content: _indexPage(c, page, search, unusedOnly, sort, total, messages),
      ),
    );
  }

  /// `/tags/new`.
  Future<Response> create(Request request) async {
    final (c, form, failure) = await _begin(request);
    if (failure != null) return failure;
    final user = c.user!;
    if (form == null) return c.html(_newDialog(c, null, const []));

    final (name, errors) = await _cleanName(form['name'], user.id);
    if (errors.isNotEmpty) {
      return _replaceDialog(c, _newDialog(c, form['name'], errors));
    }
    (await TagsRepo(_db).insert(name, DateTime.now().toUtc(), user.id)).orThrow;
    await web.addMessage(c, 'Tag "$name" created successfully.');
    return c.redirect('/tags');
  }

  /// `/tags/<id>/edit`: renaming a tag.
  Future<Response> edit(Request request) async {
    final (c, form, failure) = await _begin(request);
    if (failure != null) return failure;
    final user = c.user!;
    final tag = await _owned(await request.path<String>('id'), user.id);
    if (tag == null) return notFoundPage();
    if (form == null) return c.html(_editDialog(c, tag, tag.name, const []));

    final (name, errors) = await _cleanName(
      form['name'],
      user.id,
      except: tag.id,
    );
    if (errors.isNotEmpty) {
      return _replaceDialog(c, _editDialog(c, tag, form['name'], errors));
    }
    (await TagsRepo(_db).rename(tag.id, user.id, name)).orThrow;
    return c.redirect(_withQuery('/tags', c));
  }

  /// `/tags/merge`: moves the bookmarks of some tags to another, then
  /// deletes those tags.
  Future<Response> merge(Request request) async {
    final (c, form, failure) = await _begin(request);
    if (failure != null) return failure;
    final user = c.user!;
    if (form == null) {
      return c.html(_mergeDialog(c, null, null, const {}));
    }

    final errors = <String, List<String>>{'target_tag': [], 'merge_tags': []};
    TagRow? target;
    final targetField = cleanChar(form['target_tag'], required: true);
    errors['target_tag']!.addAll(targetField.errors);
    if (targetField.errors.isEmpty) {
      final names = parseTagString(targetField.value, delimiter: ' ');
      if (names.length != 1) {
        errors['target_tag']!.add(
          'Please enter only one tag name for the target tag.',
        );
      } else {
        target = (await TagsRepo(_db).named(user.id, names.single)).orThrow;
        if (target == null) {
          errors['target_tag']!.add('Tag "${names.single}" does not exist.');
        }
      }
    }
    final merged = <TagRow>[];
    final mergeField = cleanChar(form['merge_tags'], required: true);
    errors['merge_tags']!.addAll(mergeField.errors);
    if (mergeField.errors.isEmpty) {
      final names = parseTagString(mergeField.value, delimiter: ' ');
      if (names.isEmpty) {
        errors['merge_tags']!.add('Please enter at least one tag to merge.');
      }
      for (final name in names) {
        final tag = (await TagsRepo(_db).named(user.id, name)).orThrow;
        if (tag == null) {
          errors['merge_tags']!.add('Tag "$name" does not exist.');
          break;
        }
        merged.add(tag);
      }
      if (errors['merge_tags']!.isEmpty &&
          target != null &&
          merged.any((t) => t.id == target!.id)) {
        errors['merge_tags']!.add(
          'The target tag cannot be selected for merging.',
        );
      }
    }
    if (errors.values.any((e) => e.isNotEmpty)) {
      return _replaceDialog(
        c,
        _mergeDialog(c, form['target_tag'], form['merge_tags'], errors),
      );
    }

    (await TagsRepo(
      _db,
    ).merge(user.id, target!.id, [for (final t in merged) t.id])).orThrow;
    await web.addMessage(
      c,
      'Successfully merged ${merged.length} tags '
      '(${merged.map((t) => t.name).join(', ')}) into "${target.name}".',
    );
    return c.redirect('/tags');
  }

  /// The page context and, for a `POST`, its form, or the response that
  /// ends the request: a failed CSRF check or a visitor to send to sign in.
  Future<(PageContext, FormData?, Response?)> _begin(Request request) async {
    final c = await web.context(request);
    FormData? form;
    if (request.method == 'POST') {
      form = await readFormData(request);
      final failure = Sessions.csrfFailure(
        request,
        form['csrfmiddlewaretoken'],
      );
      if (failure != null) return (c, form, csrfFailurePage(c, failure));
    }
    if (!c.isAuthenticated) return (c, form, redirectToLogin(c));
    return (c, form, null);
  }

  Future<TagRow?> _owned(String? id, int ownerId) async {
    final tagId = int.tryParse(id ?? '');
    if (tagId == null || tagId > 2147483647) return null;
    return (await TagsRepo(_db).owned(tagId, ownerId)).orThrow;
  }

  /// `TagForm.clean_name` and the model's length limit.
  Future<(String, List<String>)> _cleanName(
    String? raw,
    int ownerId, {
    int? except,
  }) async {
    final field = cleanChar(raw, required: true);
    if (field.errors.isNotEmpty) return ('', field.errors);
    final name = sanitizeTagName(field.value);
    final existing = (await TagsRepo(_db).named(ownerId, name)).orThrow;
    if (existing != null && existing.id != except) {
      return (name, ['Tag "$name" already exists.']);
    }
    return (name, cleanChar(name, maxLength: 64).errors);
  }

  /// `turbo.stream(turbo.replace("tag-modal", ..., method="morph"))`.
  static Response _replaceDialog(PageContext c, String dialog) =>
      turboStream(c, [turboReplace('tag-modal', dialog, method: 'morph')]);

  static String _withQuery(String url, PageContext c) {
    final query = urlencode([
      for (final MapEntry(:key, :value) in QueryParams.parse(
        c.request.requestedUri.query,
      ).last.entries)
        (key, value),
    ]);
    return query.isEmpty ? url : '$url?$query';
  }

  /// Django's escaping of `icontains` values for `LIKE`.
  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  String _indexPage(
    PageContext c,
    Page<TagUsageRow> page,
    String search,
    bool unusedOnly,
    String sort,
    int total,
    List<MessageRow> messages,
  ) {
    final query = QueryParams.parse(c.request.requestedUri.query).encode();
    String option(String value, String label) =>
        '<option value="$value" ${sort == value ? 'selected' : ''}>$label</option>';
    final filtered = search.isNotEmpty || unusedOnly;
    final String list;
    if (page.items.isEmpty) {
      list = filtered
          ? '''
        <div class="empty">
            <p class="empty-title h5">No tags found</p>
            <p class="empty-subtitle">Try adjusting your search or filters</p>
        </div>'''
          : '''
        <div class="empty">
            <p class="empty-title h5">You have no tags yet</p>
            <p class="empty-subtitle">Tags will appear here when you add bookmarks with tags</p>
        </div>''';
    } else {
      final rows = [
        for (final tag in page.items)
          '''
                <tr>
                  <td>${e(tag.name)}</td>
                  <td style="width: 25%">
                    <a class="btn btn-link"
                       data-turbo-frame="_top"
                       href="/bookmarks?q=%23${e(q(tag.name))}">
                      ${tag.bookmarkCount}
                    </a>
                  </td>
                  <td class="actions">
                    <a class="btn btn-link"
                       href="/tags/${tag.id}/edit?${e(query)}"
                       data-turbo-frame="tag-modal">Edit</a>
                    <button type="submit"
                            name="delete_tag"
                            value="${tag.id}"
                            class="btn btn-link text-error"
                            data-confirm>Remove</button>
                  </td>
                </tr>''',
      ].join('\n');
      list =
          '''
        <form method="post">
          ${c.csrfInput}
          <table class="table crud-table">
            <thead>
              <tr>
                <th>Name</th>
                <th style="width: 25%">Bookmarks</th>
                <th class="actions">
                  <span class="text-assistive">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody>
$rows
            </tbody>
          </table>
        </form>
${pagination(c, page)}''';
    }
    return '''
  <div class="tags-page crud-page">
    <turbo-frame id="tag-main">
    <main aria-labelledby="main-heading">
      <div class="crud-header">
        <h1 id="main-heading">Tags</h1>
        <div class="d-flex gap-2 ml-auto">
          <a href="/tags/new"
             data-turbo-frame="tag-modal"
             class="btn">Create Tag</a>
          <a href="/tags/merge"
             data-turbo-frame="tag-modal"
             class="btn">Merge Tags</a>
        </div>
      </div>
${messageList(messages)}
      <div class="crud-filters">
        <ld-form data-form-reset>
          <form method="get" class="mb-2" data-turbo-frame="_top">
            <div class="form-group">
              <label class="form-label text-assistive" for="search">Search tags</label>
              <div class="input-group">
                <input type="text"
                       id="search"
                       name="search"
                       value="${e(search)}"
                       placeholder="Search tags..."
                       class="form-input">
                <button type="submit" class="btn input-group-btn">Search</button>
              </div>
            </div>
            <div class="form-group">
              <label class="form-label text-assistive" for="sort">Sort by</label>
              <div class="input-group">
                <span class="input-group-addon text-secondary">
                  <svg width="20" height="20">
                    <use href="${static('icons.svg')}?v=$linkdingVersion#sort"></use>
                  </svg>
                </span>
                <select id="sort" name="sort" class="form-select" data-submit-on-change>
                  ${option('name-asc', 'Name A-Z')}
                  ${option('name-desc', 'Name Z-A')}
                  ${option('count-asc', 'Fewest bookmarks')}
                  ${option('count-desc', 'Most bookmarks')}
                </select>
              </div>
            </div>
            <div class="form-group">
              <label class="form-checkbox">
                <input type="checkbox"
                       name="unused"
                       value="true"
                       ${unusedOnly ? 'checked' : ''}
                       data-submit-on-change>
                <i class="form-icon"></i> Show only unused tags
              </label>
            </div>
          </form>
        </ld-form>
        <p class="text-secondary text-small m-0">
          ${filtered ? 'Showing ${page.total} of $total tags' : '$total tags total'}
        </p>
      </div>
$list
    </main>
    <turbo-frame id="tag-modal"></turbo-frame>
    </turbo-frame>
  </div>''';
  }

  /// `tags/form.html`.
  String _nameField(String? value, List<String> errors) =>
      '''
<div class="form-group">
  ${fieldLabel('name', 'Name')}
  ${inputField('text', 'name', value, fieldAttributes('name', widget: const {'class': 'form-input', 'autocomplete': 'off'}, required: true, hasHelp: true, errors: errors, extra: const {'autofocus': true}))}
  ${fieldHelp('name', '''
    Tag names are case-insensitive and cannot contain spaces (spaces will be replaced with hyphens).
  ''')}
  ${errorList('name', errors)}
</div>''';

  String _dialog(
    PageContext c, {
    required String action,
    required String target,
    required String closeUrl,
    required String title,
    required String body,
    String modalClass = 'modal tag-edit-modal active',
    String submit = 'Save',
  }) =>
      '''
<turbo-frame id="tag-modal">
<form method="post"
      action="${e(action)}"
      data-turbo-frame="$target"
      novalidate>
  ${c.csrfInput}
  <ld-modal class="$modalClass"
            data-close-url="${e(closeUrl)}"
            data-turbo-frame="tag-modal">
    <div class="modal-overlay" data-close-modal></div>
    <div class="modal-container" role="dialog" aria-modal="true">
${modalHeader(title)}
      <div class="modal-body">$body</div>
      <div class="modal-footer d-flex justify-between">
        <button type="button" class="btn btn-wide" data-close-modal>Cancel</button>
        <button type="submit" class="btn btn-primary btn-wide">$submit</button>
      </div>
    </div>
  </ld-modal>
</form>
</turbo-frame>''';

  /// `tags/new.html`.
  String _newDialog(PageContext c, String? name, List<String> errors) =>
      _dialog(
        c,
        action: '/tags/new',
        target: '_top',
        closeUrl: '/tags',
        title: 'Create Tag',
        body: _nameField(name, errors),
      );

  /// `tags/edit.html`, keeping the page's filters in both addresses.
  String _editDialog(
    PageContext c,
    TagRow tag,
    String? name,
    List<String> errors,
  ) {
    final query = QueryParams.parse(c.request.requestedUri.query).encode();
    return _dialog(
      c,
      action: '/tags/${tag.id}/edit?$query',
      target: 'tag-main',
      closeUrl: '/tags?$query',
      title: 'Edit Tag',
      body: _nameField(name, errors),
    );
  }

  /// `tags/merge.html`.
  String _mergeDialog(
    PageContext c,
    String? target,
    String? merge,
    Map<String, List<String>> errors,
  ) {
    String tagField(String name, String label, String? value, String help) {
      final fieldErrors = errors[name] ?? const [];
      final attrs = fieldAttributes(
        name,
        required: true,
        hasHelp: true,
        errors: fieldErrors,
      );
      final classes = attrs['class'];
      return '''
        <div class="form-group">
          ${fieldLabel(name, label)}
          <ld-tag-autocomplete input-id="id_$name" input-name="$name" input-value="${e(value ?? '')}" input-aria-describedby="${attrs['aria-describedby']}"${classes == null ? '' : ' input-class="$classes"'}></ld-tag-autocomplete>
          ${fieldHelp(name, help)}
          ${errorList(name, fieldErrors)}
        </div>''';
    }

    return _dialog(
      c,
      action: '/tags/merge',
      target: '_top',
      closeUrl: '/tags',
      title: 'Merge Tags',
      modalClass: 'modal active',
      submit: 'Merge Tags',
      body:
          '''
        <details class="mb-4">
          <summary>
            <span class="text-bold mb-1">How to merge tags</span>
          </summary>
          <ol>
            <li>Enter the name of the tag you want to keep</li>
            <li>Enter the names of tags to merge into the target tag</li>
            <li>The target tag is added to all bookmarks that have any of the merge tags</li>
            <li>The merged tags are deleted</li>
          </ol>
        </details>
${tagField('target_tag', 'Target tag', target, '''
            Enter the name of the tag you want to keep. The tags entered below will be merged into this one.
          ''')}
${tagField('merge_tags', 'Tags to merge', merge, '''
            Enter the names of tags to merge into the target tag, separated by spaces.
            These tags will be deleted after merging.
          ''')}
      ''',
    );
  }
}
