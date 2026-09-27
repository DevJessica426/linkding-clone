import 'package:dust_server/server.dart';

import '../auth/sessions.dart';
import '../compat/django.dart';
import '../compat/form_data.dart';
import '../core/urls.dart';
import '../db/bookmarks_repo.dart';
import '../services/bookmarks.dart';
import '../services/errors.dart';
import 'context.dart';
import 'forms.dart';
import 'html.dart';
import 'layout.dart';

/// linkding's `BookmarkForm` and the `new`, `edit` and `close` views.
final class BookmarkFormViews {
  BookmarkFormViews(this.web);

  final Web web;

  /// `/bookmarks/new`: prefilled from the query string, as the bookmarklet
  /// and browser extension open it.
  Future<Response> create(Request request) async {
    final c = await web.context(request);
    final submitted = await _submitted(request, c);
    if (submitted case (final Response failure, _)) return failure;
    if (!c.isAuthenticated) return redirectToLogin(c);
    final profile = c.profile.row;

    final _Form form;
    if (submitted case (_, final FormData data?)) {
      form = _Form.bound(data);
      _validate(form);
      form.hasNotes = form.cleaned['notes']!.isNotEmpty;
      if (form.isValid) {
        await web.bookmarks.create(
          form.draft(),
          form.tagString,
          c.user!.id,
          c.profile,
          scrape: false,
        );
        return c.redirect(form.isAutoClose ? '/bookmarks/close' : '/bookmarks');
      }
    } else {
      final query = c.query;
      form = _Form(
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
    return c.html(
      _page(
        c,
        heading: 'New bookmark',
        action: '/bookmarks/new',
        form: form,
        returnUrl: '/bookmarks',
        bookmarkId: 0,
      ),
      status: form.isBound ? 422 : 200,
    );
  }

  /// `/bookmarks/<id>/edit`, back to `return_url` when saved.
  Future<Response> edit(Request request) async {
    final c = await web.context(request);
    final submitted = await _submitted(request, c);
    if (submitted case (final Response failure, _)) return failure;
    if (!c.isAuthenticated) return redirectToLogin(c);
    final user = c.user!;

    final id = int.tryParse(await request.path<String>('id'));
    final bookmark = id == null || id > 2147483647
        ? null
        : (await BookmarksRepo(
            web.database.connection,
          ).owned(id, user.id)).orThrow;
    if (bookmark == null) return notFoundPage();
    final returnUrl = safeReturnUrl(c.query['return_url'], '/bookmarks');

    final _Form form;
    if (submitted case (_, final FormData data?)) {
      form = _Form.bound(data);
      _validate(form);
      // A model form's initial values are the saved bookmark's.
      form.hasNotes =
          bookmark.notes.isNotEmpty || form.cleaned['notes']!.isNotEmpty;
      if (form.errors['url']!.isEmpty &&
          (await BookmarksRepo(web.database.connection).duplicate(
            user.id,
            normalizeUrl(form.url),
            form.url!,
            bookmark.id,
          )).orThrow) {
        form.errors['url']!.add('A bookmark with this URL already exists.');
      }
      if (form.isValid) {
        await web.bookmarks.update(
          bookmark.id,
          form.draft(
            isArchived: bookmark.isArchived,
            dateAdded: bookmark.dateAdded,
          ),
          form.tagString,
          user.id,
          c.profile,
        );
        return c.redirect(returnUrl);
      }
    } else {
      final tags = await web.bookmarks.tagNames([bookmark.id]);
      form = _Form(
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
    return c.html(
      _page(
        c,
        heading: 'Edit bookmark',
        action: '/bookmarks/${bookmark.id}/edit?return_url=${q(returnUrl)}',
        form: form,
        returnUrl: returnUrl,
        bookmarkId: bookmark.id,
      ),
      status: form.isBound ? 422 : 200,
    );
  }

  /// `/bookmarks/close`, where a popup goes after saving.
  Future<Response> close(Request request) async {
    final c = await web.context(request);
    if (!c.isAuthenticated) return redirectToLogin(c);
    return c.html(
      layout(
        c,
        title: 'Linkding',
        content: '''
  <script type="application/javascript">
    window.close()
  </script>
  <p>You can now close this window.</p>''',
      ),
    );
  }

  /// A posted form, or the CSRF failure page for one without a valid token;
  /// `(null, null)` for other methods.
  static Future<(Response?, FormData?)> _submitted(
    Request request,
    PageContext c,
  ) async {
    if (request.method != 'POST') return (null, null);
    final data = await readFormData(request);
    final failure = Sessions.csrfFailure(request, data['csrfmiddlewaretoken']);
    if (failure != null) return (csrfFailurePage(c, failure), null);
    return (null, data);
  }

  /// The form's field checks, then the model's.
  void _validate(_Form form) {
    final url = cleanChar(form.rawUrl, required: true);
    form.url = url.value;
    form.errors['url']!.addAll(url.errors);
    if (url.errors.isEmpty && !web.config.disableUrlValidation) {
      if (!isValidUrl(url.value)) form.errors['url']!.add('Enter a valid URL.');
    }
    if (form.errors['url']!.isEmpty) {
      final model = cleanChar(url.value, maxLength: 2048);
      form.errors['url']!.addAll(model.errors);
    }
    for (final (name, maxLength) in const [
      ('title', 512),
      ('description', null),
      ('notes', null),
      ('tag_string', null),
    ]) {
      final field = cleanChar(form.raw[name], maxLength: maxLength);
      form.errors[name]!.addAll(field.errors);
      form.cleaned[name] = field.value;
    }
  }

  String _page(
    PageContext c, {
    required String heading,
    required String action,
    required _Form form,
    required String returnUrl,
    required int bookmarkId,
  }) {
    final profile = c.profile.row;
    final errors = form.errors;
    final sharedHelp = profile.enablePublicSharing
        ? 'Share this bookmark with other registered users and anonymous users.'
        : 'Share this bookmark with other registered users.';
    final shared = profile.enableSharing
        ? '''
    <div class="form-group">
      ${checkboxField('shared', form.shared, 'Share', fieldAttributes('shared', hasHelp: true))}
      ${fieldHelp('shared', sharedHelp)}
    </div>'''
        : '';
    final submit = form.isAutoClose
        ? '<input type="submit" value="Save and close" class="btn btn-primary btn-wide">'
        : '''<input type="submit"
             value="Save"
             class="btn btn-primary btn btn-primary btn-wide">''';
    const text = {'class': 'form-input', 'autocomplete': 'off'};
    const textarea = {'cols': '40', 'rows': '10', 'class': 'form-input'};
    final tagAttributes = fieldAttributes('tag_string', hasHelp: true);

    return layout(
      c,
      title: '$heading - Linkding',
      content:
          '''
  <div class="bookmarks-form-page">
    <main aria-labelledby="main-heading">
      <div class="section-header">
        <h1 id="main-heading">$heading</h1>
      </div>
      <ld-form data-submit-on-ctrl-enter>
        <form action="${e(action)}" method="post" novalidate>
<div class="bookmarks-form">
  ${c.csrfInput}
  ${hiddenInput('auto_close', form.autoClose)}
  <div class="form-group">
    ${fieldLabel('url', 'URL')}
    <div class="has-icon-right">
      ${inputField('text', 'url', form.rawUrl, fieldAttributes('url', widget: text, required: true, errors: errors['url']!, extra: const {'autofocus': true}))}
      <i class="form-icon loading"></i>
    </div>
    ${errorList('url', errors['url']!)}
    <div class="form-input-hint bookmark-exists">
      This URL is already bookmarked.
      The form has been pre-filled with the existing bookmark, and saving the form will update the existing bookmark.
    </div>
  </div>
  <div class="form-group">
    ${fieldLabel('tag_string', 'Tags')}
    <ld-tag-autocomplete input-id="id_tag_string" input-name="tag_string" input-value="${e(form.raw['tag_string'] ?? '')}" input-aria-describedby="${tagAttributes['aria-describedby']}"></ld-tag-autocomplete>
    ${fieldHelp('tag_string', '''
      Enter any number of tags separated by space and <strong>without</strong> the hash (#).
      If a tag does not exist it will be automatically created.
    ''')}
    <div class="form-input-hint auto-tags"></div>
  </div>
  <div class="form-group">
    <div class="d-flex justify-between align-baseline">
      ${fieldLabel('title', 'Title')}
      <div class="flex">
        <button id="refresh-button" class="btn btn-link suffix-button" type="button">Refresh from website</button>
        <ld-clear-button data-for="id_title">
          <button class="ml-2 btn btn-link suffix-button" type="button">Clear</button>
        </ld-clear-button>
      </div>
    </div>
    ${inputField('text', 'title', form.raw['title'], fieldAttributes('title', widget: {...text, 'maxlength': '512'}, errors: errors['title']!))}
  </div>
  <div class="form-group">
    <div class="d-flex justify-between align-baseline">
      ${fieldLabel('description', 'Description')}
      <ld-clear-button data-for="id_description">
        <button class="btn btn-link suffix-button" type="button">Clear</button>
      </ld-clear-button>
    </div>
    ${textareaField('description', form.raw['description'], fieldAttributes('description', widget: textarea, errors: errors['description']!, extra: const {'rows': '3'}))}
  </div>
  <div class="form-group">
    <details class="notes"${form.hasNotes ? ' open' : ''}>
      <summary>
        <span class="form-label d-inline-block">Notes</span>
      </summary>
      <label for="id_notes" class="text-assistive">Notes</label>
      ${textareaField('notes', form.raw['notes'], fieldAttributes('notes', widget: textarea, hasHelp: true, errors: errors['notes']!, extra: const {'rows': '8'}))}
      ${fieldHelp('notes', '''
        Additional notes, supports Markdown.
      ''')}
    </details>
  </div>
  <div class="form-group">
    ${checkboxField('unread', form.unread, 'Mark as unread', fieldAttributes('unread', hasHelp: true))}
    ${fieldHelp('unread', '''
      Unread bookmarks can be filtered for, and marked as read after you had a chance to look at them.
    ''')}
  </div>
$shared
  <div class="divider"></div>
  <div class="form-group d-flex justify-between">
      $submit
    <a href="${e(returnUrl)}" class="btn">Cancel</a>
  </div>
${_formScript(bookmarkId)}
</div>
        </form>
      </ld-form>
    </main>
  </div>''',
    );
  }
}

/// linkding's `get_safe_return_url`: a path on this site, or [fallback].
String safeReturnUrl(String? returnUrl, String fallback) =>
    returnUrl == null || !RegExp('^/[a-z]+').hasMatch(returnUrl)
    ? fallback
    : returnUrl;

/// What the form holds: the values to show, and once submitted, the
/// cleaned values and errors.
final class _Form {
  _Form({
    String? url,
    String? title,
    String? description,
    String? notes,
    String? tagString,
    this.autoClose,
    this.unread = false,
    this.shared = false,
    this.hasNotes = false,
  }) : rawUrl = url,
       isBound = false,
       raw = {
         'title': title,
         'description': description,
         'notes': notes,
         'tag_string': tagString,
       };

  /// A submitted form shows what was sent. A checkbox counts as ticked
  /// unless its value is missing, empty, `false` or `0`. A field that was
  /// not sent at all saves as empty: none of these fields has a default
  /// that Django's `construct_instance` would keep instead.
  _Form.bound(FormData data)
    : rawUrl = data['url'],
      isBound = true,
      autoClose = data['auto_close'],
      unread = _checked(data['unread']),
      shared = _checked(data['shared']),
      hasNotes = false,
      raw = {
        'title': data['title'],
        'description': data['description'],
        'notes': data['notes'],
        'tag_string': data['tag_string'],
      };

  static bool _checked(String? value) =>
      value != null &&
      value.isNotEmpty &&
      !const {'false', '0'}.contains(value.toLowerCase());

  final bool isBound;
  final String? rawUrl;
  final Map<String, String?> raw;
  final String? autoClose;
  final bool unread;
  final bool shared;
  bool hasNotes;

  String? url;
  final cleaned = <String, String>{};
  final errors = <String, List<String>>{
    'url': [],
    'title': [],
    'description': [],
    'notes': [],
    'tag_string': [],
  };

  bool get isValid => errors.values.every((e) => e.isEmpty);

  /// A popup opened with `?auto_close` closes itself after saving.
  bool get isAutoClose => autoClose == 'True';

  /// The tag string as `BookmarkForm.save` passes it on: the raw input with
  /// spaces turned into commas.
  String get tagString => (raw['tag_string'] ?? '').replaceAll(' ', ',');

  BookmarkDraft draft({bool isArchived = false, DateTime? dateAdded}) =>
      BookmarkDraft(
        url: url!,
        title: cleaned['title']!,
        description: cleaned['description']!,
        notes: cleaned['notes']!,
        unread: unread,
        shared: shared,
        isArchived: isArchived,
        dateAdded: dateAdded,
      );
}

/// linkding's script for the bookmark form (`bookmarks/form.html`),
/// verbatim: it fills in the title and description from the page and
/// points out an existing bookmark for the URL.
String _formScript(int bookmarkId) =>
    r'''
  <script type="application/javascript">
    /**
     * - Pre-fill title and description with metadata from website as soon as URL changes
     * - Show hint if URL is already bookmarked
     */
    (function init() {
      const urlInput = document.getElementById('id_url');
      const titleInput = document.getElementById('id_title');
      const descriptionInput = document.getElementById('id_description');
      const notesDetails = document.querySelector('form details.notes');
      const notesInput = document.getElementById('id_notes');
      const unreadCheckbox = document.getElementById('id_unread');
      const sharedCheckbox = document.getElementById('id_shared');
      const refreshButton = document.getElementById('refresh-button');
      const bookmarkExistsHint = document.querySelector('.form-input-hint.bookmark-exists');
      const editedBookmarkId = parseInt('__BOOKMARK_ID__');
      let isTitleModified = !!titleInput.value;
      let isDescriptionModified = !!descriptionInput.value;

      function toggleLoadingIcon(input, show) {
        const icon = input.parentNode.querySelector('i.form-icon');
        icon.style['visibility'] = show ? 'visible' : 'hidden';
      }

      function updateInput(input, value) {
        if (!input) {
          return;
        }
        input.value = value;
        input.dispatchEvent(new Event('value-changed'));
      }

      function updateCheckbox(input, value) {
        if (!input) {
          return;
        }
        input.checked = value;
      }

      function checkUrl() {
        if (!urlInput.value) {
          return;
        }

        toggleLoadingIcon(urlInput, true);

        const websiteUrl = encodeURIComponent(urlInput.value);
        const requestUrl = `/api/bookmarks/check?url=${websiteUrl}`;
        fetch(requestUrl)
          .then(response => response.json())
          .then(data => {
            const metadata = data.metadata;
            toggleLoadingIcon(urlInput, false);

            // Display hint if URL is already bookmarked
            const existingBookmark = data.bookmark;
            bookmarkExistsHint.style['display'] = existingBookmark ? 'block' : 'none';
            refreshButton.style['display'] = existingBookmark ? 'inline-block' : 'none';

            // Prefill form with existing bookmark data
            if (existingBookmark) {
              // Workaround: tag input will be replaced by tag autocomplete, so
              // defer getting the input until we need it
              const tagsInput = document.getElementById('id_tag_string');

              bookmarkExistsHint.style['display'] = 'block';
              notesDetails.open = !!existingBookmark.notes;
              updateInput(titleInput, existingBookmark.title);
              updateInput(descriptionInput, existingBookmark.description);
              updateInput(notesInput, existingBookmark.notes);
              updateInput(tagsInput, existingBookmark.tag_names.join(" "));
              updateCheckbox(unreadCheckbox, existingBookmark.unread);
              updateCheckbox(sharedCheckbox, existingBookmark.shared);
            } else {
              // Update title and description with website metadata, unless they have been modified
              if (!isTitleModified) {
                updateInput(titleInput, metadata.title);
              }
              if (!isDescriptionModified) {
                updateInput(descriptionInput, metadata.description);
              }
            }

            // Preview auto tags
            const autoTags = data.auto_tags;
            const autoTagsHint = document.querySelector('.form-input-hint.auto-tags');

            if (autoTags.length > 0) {
              autoTags.sort();
              autoTagsHint.style['display'] = 'block';
              autoTagsHint.innerHTML = `Auto tags: ${autoTags.join(" ")}`;
            } else {
              autoTagsHint.style['display'] = 'none';
            }
          });
      }

      function refreshMetadata() {
        if (!urlInput.value) {
          return;
        }

        toggleLoadingIcon(urlInput, true);

        const websiteUrl = encodeURIComponent(urlInput.value);
        const requestUrl = `/api/bookmarks/check?url=${websiteUrl}&ignore_cache=true`;

        fetch(requestUrl)
          .then(response => response.json())
          .then(data => {
            const metadata = data.metadata;
            const existingBookmark = data.bookmark;
            toggleLoadingIcon(urlInput, false);

            if (metadata.title && metadata.title !== existingBookmark?.title) {
              titleInput.value = metadata.title;
              titleInput.classList.add("modified");
            }

            if (metadata.description && metadata.description !== existingBookmark?.description) {
              descriptionInput.value = metadata.description;
              descriptionInput.classList.add("modified");
            }
          });
      }

      refreshButton.addEventListener('click', refreshMetadata);

      // Fetch website metadata when page loads and when URL changes, unless we are editing an existing bookmark
      if (!editedBookmarkId) {
        function debounce(callback, delay = 500) {
          let timeoutId;
          return (...args) => {
            clearTimeout(timeoutId);
            timeoutId = setTimeout(() => {
              timeoutId = null;
              callback(...args);
            }, delay);
          };
        }

        checkUrl();
        urlInput.addEventListener('input', debounce(checkUrl));
        titleInput.addEventListener('input', () => {
          isTitleModified = true;
        });
        descriptionInput.addEventListener('input', () => {
          isDescriptionModified = true;
        });
      } else {
        refreshButton.style['display'] = 'inline-block';
      }
    })();
  </script>
'''
        .replaceFirst('__BOOKMARK_ID__', '$bookmarkId');
