import 'package:dust_dart/db.dart';
import 'package:dust_server/server.dart';
import 'package:linkding_shared/linkding_shared.dart';

import '../auth/sessions.dart';
import '../compat/form_data.dart';
import '../config.dart';
import '../db/bundles_repo.dart';
import '../db/rows.dart';
import '../services/errors.dart';
import '../services/search.dart';
import 'bookmark_list.dart';
import 'context.dart';
import 'format.dart';
import 'forms.dart';
import 'html.dart';
import 'layout.dart';
import 'query_params.dart';

/// linkding's `views/bundles.py`: the bundle list with its ordering, and
/// the editor with a live preview of what a bundle matches.
final class BundleViews {
  BundleViews(this.web);

  final Web web;

  Executor get _db => web.database.connection;

  /// `/bundles`.
  Future<Response> index(Request request) async {
    final (c, _, failure) = await _begin(request);
    if (failure != null) return failure;
    final bundles = (await BundlesRepo(_db).all(c.user!.id)).orThrow;
    final messages = await web.takeMessages(c);
    return c.html(
      layout(
        c,
        title: 'Bundles - Linkding',
        content: _indexPage(c, bundles, messages),
      ),
    );
  }

  /// `/bundles/action`: removing a bundle, or moving one to a new place.
  Future<Response> action(Request request) async {
    final (c, form, failure) = await _begin(request);
    if (failure != null) return failure;
    final user = c.user!;
    if (form != null && form.has('remove_bundle')) {
      final bundle = await _owned(form['remove_bundle'], user.id);
      if (bundle == null) return notFoundPage();
      (await BundlesRepo(_db).delete(bundle.id, user.id)).orThrow;
      (await BundlesRepo(_db).renumber(user.id)).orThrow;
      await web.addMessage(c, "Bundle '${bundle.name}' removed successfully.");
    } else if (form != null && form.has('move_bundle')) {
      final bundle = await _owned(form['move_bundle'], user.id);
      if (bundle == null) return notFoundPage();
      final position = int.tryParse(form['move_position']?.trim() ?? '');
      if (position == null) {
        return Response(
          400,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      await _move(bundle, position, user.id);
    }
    return c.redirect('/bundles');
  }

  /// `/bundles/new`, prefilled from a search with `?q=`.
  Future<Response> create(Request request) async {
    final (c, form, failure) = await _begin(request);
    if (failure != null) return failure;
    final initial = <String, String>{};
    if (form == null) {
      final q = c.query['q'];
      if (q != null && q.isNotEmpty) {
        final parsed = LegacyQuery.parse(q);
        if (parsed.searchTerms.isNotEmpty) {
          initial['search'] = parsed.searchTerms.join(' ');
        }
        if (parsed.tagNames.isNotEmpty) {
          initial['all_tags'] = parsed.tagNames.join(' ');
        }
      }
    }
    return _editor(c, form, null, initial);
  }

  /// `/bundles/<id>/edit`.
  Future<Response> edit(Request request) async {
    final (c, form, failure) = await _begin(request);
    if (failure != null) return failure;
    final bundle = await _owned(await request.path<String>('id'), c.user!.id);
    if (bundle == null) return notFoundPage();
    return _editor(c, form, bundle, const {});
  }

  /// `/bundles/preview`: the preview frame for the fields in the query.
  Future<Response> preview(Request request) async {
    final (c, _, failure) = await _begin(request);
    if (failure != null) return failure;
    final values = _Values.fromData(c.query, null);
    return c.html(await _preview(c, values.toBundle(c.user!.id)));
  }

  /// `_handle_edit`.
  Future<Response> _editor(
    PageContext c,
    FormData? form,
    BundleRow? bundle,
    Map<String, String> initial,
  ) async {
    final user = c.user!;
    final _Values values;
    final errors = <String, List<String>>{};
    if (form != null) {
      values = _Values.fromData({
        for (final MapEntry(:key, :value) in form.fields.entries)
          key: value.last,
      }, bundle);
      errors.addAll(values.validate());
      if (errors.values.every((e) => e.isEmpty)) {
        final repo = BundlesRepo(_db);
        final now = DateTime.now().toUtc();
        if (bundle == null) {
          (await repo.insert(
            values.name,
            values.search,
            values.anyTags,
            values.allTags,
            values.excludedTags,
            (await repo.nextOrder(user.id)).orThrow,
            now,
            user.id,
            values.filterShared,
            values.filterUnread,
          )).orThrow;
        } else {
          (await repo.update(
            bundle.id,
            values.name,
            values.search,
            values.anyTags,
            values.allTags,
            values.excludedTags,
            bundle.order,
            now,
            values.filterShared,
            values.filterUnread,
          )).orThrow;
        }
        await web.addMessage(c, 'Bundle saved successfully.');
        return c.redirect('/bundles');
      }
    } else {
      values = _Values.initial(bundle, initial);
    }

    // The preview shows the saved bundle while nothing has been typed, and
    // otherwise what the form holds.
    // A new form, not bound to the bundle, so a filter left out is "off".
    final previewed = form == null && bundle != null
        ? bundle
        : _Values.fromData(
            form == null
                ? {...c.query, ...initial}
                : {
                    for (final MapEntry(:key, :value) in form.fields.entries)
                      key: value.last,
                  },
            null,
          ).toBundle(user.id);
    final heading = bundle == null ? 'New bundle' : 'Edit bundle';
    final messages = await web.takeMessages(c);
    return c.html(
      layout(
        c,
        title: '$heading - Linkding',
        content:
            '''
  <div class="bundles-editor-page grid columns-md-1">
    <main aria-labelledby="main-heading">
      <div class="section-header">
        <h1 id="main-heading">$heading</h1>
      </div>
${messageList(messages)}
      <form id="bundle-form"
            action="${bundle == null ? '/bundles/new' : '/bundles/${bundle.id}/edit'}"
            method="post"
            novalidate>
        ${c.csrfInput}
${_formFields(values, errors)}
      </form>
    </main>
    <aside class="col-2" aria-labelledby="preview-heading">
      <div class="section-header">
        <h2 id="preview-heading">Preview</h2>
      </div>
${await _preview(c, previewed)}
    </aside>
  </div>''',
      ),
      status: form != null ? 422 : 200,
    );
  }

  /// `bundles/preview.html`: the active bookmarks the bundle matches, as a
  /// list without actions.
  Future<String> _preview(PageContext c, BundleRow bundle) async {
    final user = c.user!;
    final query = QueryParams.parse(c.request.requestedUri.query);
    final candidates = await BookmarkSearchQuery(_db).run(
      list: BookmarkList.active,
      search: BookmarkSearch(bundle: bundle),
      profile: c.profile,
      ownerId: user.id,
    );
    if (candidates.isEmpty) {
      return '''
<turbo-frame id="preview">
  <div>No bookmarks match the current bundle.</div>
</turbo-frame>''';
    }
    final page = ListPage(
      kind: ListKind.active,
      links: ListLinks(ListKind.active, query, c.profile),
      query: query,
      search: BookmarkSearch(bundle: bundle),
      page: Page.of(candidates, c.profile.row.itemsPerPage, query['page']),
      owners: {user.id: user.username},
      tagCloud: TagCloud(const [], const []),
      bundles: null,
      selectedBundleId: null,
      users: null,
      details: null,
      isPreview: true,
      paginationFrame: 'preview',
    );
    return '''
<turbo-frame id="preview">
  <div class="mb-4">Found ${candidates.length} bookmarks matching this bundle.</div>
${bookmarkList(c, page)}
</turbo-frame>''';
  }

  /// `move_bundle`: takes the bundle out and puts it back at [position],
  /// as Python's `list.insert` places it, then numbers the bundles in order.
  Future<void> _move(BundleRow bundle, int position, int ownerId) async {
    final bundles = (await BundlesRepo(_db).all(ownerId)).orThrow;
    final current = bundles.indexWhere((b) => b.id == bundle.id);
    if (position == current) return;
    final ordered = [...bundles]..removeAt(current);
    var at = position < 0 ? ordered.length + position : position;
    at = at.clamp(0, ordered.length);
    ordered.insert(at, bundles[current]);
    for (final (index, b) in ordered.indexed) {
      (await BundlesRepo(_db).setOrder(b.id, index)).orThrow;
    }
  }

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

  /// `access.bundle_write`.
  Future<BundleRow?> _owned(String? id, int ownerId) async {
    final bundleId = int.tryParse(id?.trim() ?? '');
    if (bundleId == null || bundleId > 2147483647) return null;
    return (await BundlesRepo(_db).owned(bundleId, ownerId)).orThrow;
  }

  String _indexPage(
    PageContext c,
    List<BundleRow> bundles,
    List<MessageRow> messages,
  ) {
    final String list;
    if (bundles.isEmpty) {
      list = '''
      <div class="empty">
        <p class="empty-title h5">You have no bundles yet</p>
        <p class="empty-subtitle">Create your first bundle to get started</p>
      </div>''';
    } else {
      final rows = [
        for (final bundle in bundles)
          '''
              <tr data-bundle-id="${bundle.id}" draggable="true">
                <td>
                  <div class="d-flex align-center">
                    <svg class="text-secondary mr-1" width="16" height="16">
                      <use href="${static('icons.svg')}?v=$linkdingVersion#drag"></use>
                    </svg>
                    <span>${e(bundle.name)}</span>
                  </div>
                </td>
                <td class="actions">
                  <a class="btn btn-link"
                     href="/bundles/${bundle.id}/edit">Edit</a>
                  <button data-confirm
                          type="submit"
                          name="remove_bundle"
                          value="${bundle.id}"
                          class="btn btn-link">Remove</button>
                </td>
              </tr>''',
      ].join('\n');
      list =
          '''
      <form action="/bundles/action" method="post">
        ${c.csrfInput}
        <table class="table crud-table">
          <thead>
            <tr>
              <th>Name</th>
              <th class="actions">
                <span class="text-assistive">Actions</span>
              </th>
            </tr>
          </thead>
          <tbody>
$rows
          </tbody>
        </table>
        <input type="submit" name="move_bundle" value="" class="d-none">
        <input type="hidden" name="move_position" value="">
      </form>''';
    }
    return '''
  <main class="bundles-page crud-page" aria-labelledby="main-heading">
    <div class="crud-header">
      <h1 id="main-heading">Bundles</h1>
      <a href="/bundles/new" class="btn">Add bundle</a>
    </div>
${messageList(messages)}
$list
  </main>
  <script>$_reorderScript</script>''';
  }

  /// `bundles/form.html`.
  String _formFields(_Values v, Map<String, List<String>> errors) {
    List<String> errorsOf(String name) => errors[name] ?? const [];
    const text = {'class': 'form-input', 'autocomplete': 'off'};
    String tagField(String name, String label, String value, String help) {
      final attrs = fieldAttributes(
        name,
        hasHelp: true,
        errors: errorsOf(name),
      );
      final classes = attrs['class'];
      return '''
<div class="form-group">
  ${fieldLabel(name, label)}
  <ld-tag-autocomplete input-id="id_$name" input-name="$name" input-value="${e(value)}" input-aria-describedby="${attrs['aria-describedby']}"${classes == null ? '' : ' input-class="$classes"'}></ld-tag-autocomplete>
  ${fieldHelp(name, help)}
</div>''';
    }

    String selectField(
      String name,
      String label,
      List<(String, String)> choices,
      String? value,
      String help,
    ) {
      final attrs = fieldAttributes(
        name,
        widget: const {'class': 'form-select'},
        hasHelp: true,
        errors: errorsOf(name),
      );
      final options = [
        for (final (choice, text) in choices)
          '  <option value="$choice"${choice == value ? ' selected' : ''}>$text</option>\n',
      ].join('\n');
      final attributes = [
        for (final MapEntry(key: k, value: a) in attrs.entries)
          a == true ? ' $k' : ' $k="${e(a)}"',
      ].join();
      return '''
<div class="form-group">
  ${fieldLabel(name, label)}
  <select name="$name"$attributes>
$options
</select>
  ${fieldHelp(name, help)}
</div>''';
    }

    return '''
<div class="form-group">
  ${fieldLabel('name', 'Name')}
  ${inputField('text', 'name', v.rawName, fieldAttributes('name', widget: {...text, 'maxlength': '256'}, required: true, errors: errorsOf('name')))}
  ${errorList('name', errorsOf('name'))}
</div>
<div class="form-group">
  ${fieldLabel('search', 'Search terms')}
  ${inputField('text', 'search', v.rawSearch, fieldAttributes('search', widget: {...text, 'maxlength': '256'}, hasHelp: true, errors: errorsOf('search')))}
  ${errorList('search', errorsOf('search'))}
  ${fieldHelp('search', '''
    All of these search terms must be present in a bookmark to match.
  ''')}
</div>
${tagField('any_tags', 'Tags', v.rawAnyTags, '''
    At least one of these tags must be present in a bookmark to match.
  ''')}
${tagField('all_tags', 'Required tags', v.rawAllTags, '''
    All of these tags must be present in a bookmark to match.
  ''')}
${tagField('excluded_tags', 'Excluded tags', v.rawExcludedTags, '''
    None of these tags must be present in a bookmark to match.
  ''')}
${selectField('filter_unread', 'Reading State', const [('off', 'All'), ('yes', 'Unread'), ('no', 'Read')], v.shownUnread, '''
    Limit matches to unread or read bookmarks.
  ''')}
${selectField('filter_shared', 'Sharing State', const [('off', 'All'), ('yes', 'Shared'), ('no', 'Unshared')], v.shownShared, '''
    Limit matches to shared or unshared bookmarks.
  ''')}
<div class="form-footer d-flex mt-4">
  <input type="submit"
         name="save"
         value="Save"
         class="btn btn-primary btn-wide">
  <a href="/bundles"
     class="btn btn-wide ml-auto">Cancel</a>
  <a href="/bundles/preview"
     data-turbo-frame="preview"
     class="d-none"
     id="preview-link"></a>
</div>
<script>$_previewScript</script>''';
  }
}

/// A bundle form's fields: what to show, and the values it saves.
final class _Values {
  _Values({
    required this.rawName,
    required this.rawSearch,
    required this.rawAnyTags,
    required this.rawAllTags,
    required this.rawExcludedTags,
    required this.filterUnread,
    required this.filterShared,
    required this.shownUnread,
    required this.shownShared,
  });

  /// An unsubmitted form: the bundle's values, or for a new bundle the
  /// defaults and what `?q=` suggested.
  factory _Values.initial(BundleRow? bundle, Map<String, String> initial) =>
      _Values(
        rawName: bundle?.name ?? '',
        rawSearch: bundle?.search ?? initial['search'] ?? '',
        rawAnyTags: bundle?.anyTags ?? '',
        rawAllTags: bundle?.allTags ?? initial['all_tags'] ?? '',
        rawExcludedTags: bundle?.excludedTags ?? '',
        filterUnread: bundle?.filterUnread ?? 'off',
        filterShared: bundle?.filterShared ?? 'off',
        // A new model form has no initial values, so no option is chosen.
        shownUnread: bundle?.filterUnread,
        shownShared: bundle?.filterShared,
      );

  /// Submitted values. A filter left out keeps the bundle's value (the
  /// model's default for a new one); one sent empty is saved empty, as
  /// Django's `construct_instance` does for a field with a default.
  factory _Values.fromData(Map<String, String> data, BundleRow? bundle) =>
      _Values(
        rawName: data['name'] ?? '',
        rawSearch: data['search'] ?? '',
        rawAnyTags: data['any_tags'] ?? '',
        rawAllTags: data['all_tags'] ?? '',
        rawExcludedTags: data['excluded_tags'] ?? '',
        filterUnread: data['filter_unread'] ?? bundle?.filterUnread ?? 'off',
        filterShared: data['filter_shared'] ?? bundle?.filterShared ?? 'off',
        shownUnread: data['filter_unread'],
        shownShared: data['filter_shared'],
      );

  final String rawName;
  final String rawSearch;
  final String rawAnyTags;
  final String rawAllTags;
  final String rawExcludedTags;
  final String filterUnread;
  final String filterShared;

  /// The option each filter shows as chosen: what was sent, or the saved
  /// value, and none for a new bundle.
  final String? shownUnread;
  final String? shownShared;

  String get name => rawName.trim();
  String get search => rawSearch.trim();
  String get anyTags => rawAnyTags.trim();
  String get allTags => rawAllTags.trim();
  String get excludedTags => rawExcludedTags.trim();

  /// `BookmarkBundleForm` and the model's limits.
  Map<String, List<String>> validate() {
    List<String> choice(String value) =>
        value.isEmpty || const {'off', 'yes', 'no'}.contains(value)
        ? const []
        : [
            'Select a valid choice. $value is not one of the available '
                'choices.',
          ];
    return {
      'name': cleanChar(rawName, required: true, maxLength: 256).errors,
      'search': cleanChar(rawSearch, maxLength: 256).errors,
      'any_tags': cleanChar(rawAnyTags, maxLength: 1024).errors,
      'all_tags': cleanChar(rawAllTags, maxLength: 1024).errors,
      'excluded_tags': cleanChar(rawExcludedTags, maxLength: 1024).errors,
      'filter_unread': choice(filterUnread),
      'filter_shared': choice(filterShared),
    };
  }

  /// An unsaved bundle holding these values, for the preview.
  BundleRow toBundle(int ownerId) {
    final now = DateTime.now().toUtc();
    return BundleRow(
      id: 0,
      name: 'Preview Bundle',
      search: search,
      anyTags: anyTags,
      allTags: allTags,
      excludedTags: excludedTags,
      filterUnread: filterUnread,
      filterShared: filterShared,
      order: 0,
      dateCreated: now,
      dateModified: now,
      ownerId: ownerId,
    );
  }
}

/// linkding's drag-and-drop reordering script for `bundles/index.html`,
/// verbatim.
const _reorderScript = r'''
    (function init() {
      const tableBody = document.querySelector(".crud-table tbody");
      if (!tableBody) return;

      let draggedElement = null;

      const rows = tableBody.querySelectorAll('tr');
      rows.forEach((item) => {
        item.addEventListener('dragstart', handleDragStart);
        item.addEventListener('dragend', handleDragEnd);
        item.addEventListener('dragover', handleDragOver);
        item.addEventListener('dragenter', handleDragEnter);
      });

      function handleDragStart(e) {
        draggedElement = this;

        e.dataTransfer.effectAllowed = 'move';
        e.dataTransfer.dropEffect = 'move';

        this.classList.add('drag-start');
        setTimeout(() => {
          this.classList.remove('drag-start');
          this.classList.add('dragging');
        }, 0);
      }

      function handleDragEnd() {
        this.classList.remove('dragging');

        const moveBundleInput = document.querySelector('input[name="move_bundle"]');
        const movePositionInput = document.querySelector('input[name="move_position"]');
        moveBundleInput.value = draggedElement.getAttribute('data-bundle-id');
        movePositionInput.value = Array.from(tableBody.children).indexOf(draggedElement);

        const form = this.closest('form');
        form.requestSubmit(moveBundleInput);

        draggedElement = null;
      }

      function handleDragOver(e) {
        if (e.preventDefault) {
          e.preventDefault();
        }
        return false;
      }

      function handleDragEnter() {
        if (this !== draggedElement) {
          const listItems = Array.from(tableBody.children);
          const draggedIndex = listItems.indexOf(draggedElement);
          const currentIndex = listItems.indexOf(this);

          if (draggedIndex < currentIndex) {
            this.insertAdjacentElement('afterend', draggedElement);
          } else {
            this.insertAdjacentElement('beforebegin', draggedElement);
          }
        }
      }
    })();
  ''';

/// linkding's preview script for `bundles/form.html`, verbatim.
const _previewScript = r'''
  (function init() {
    const bundleForm = document.getElementById('bundle-form');
    const previewLink = document.getElementById('preview-link');

    let pendingUpdate;

    function scheduleUpdate() {
      if (pendingUpdate) {
        clearTimeout(pendingUpdate);
      }
      pendingUpdate = setTimeout(() => {
        // Ignore if link has been removed (e.g. form submit or navigation)
        if (!previewLink.isConnected) {
          return;
        }

        const baseUrl = previewLink.href.split('?')[0];
        const params = new URLSearchParams();
        const inputs = bundleForm.querySelectorAll('input[type="text"]:not([name="csrfmiddlewaretoken"]), textarea, select');

        inputs.forEach(input => {
          if (input.name && input.value.trim()) {
            params.set(input.name, input.value.trim());
          }
        });

        previewLink.href = params.toString() ? `${baseUrl}?${params.toString()}` : baseUrl;
        previewLink.click();
      }, 500)
    }

    bundleForm.addEventListener('input', scheduleUpdate);
  })();
''';
