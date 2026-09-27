import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dust_dart/db.dart';
import 'package:dust_server/server.dart';

import '../auth/sessions.dart';
import '../compat/form_data.dart';
import '../config.dart';
import '../core/profile.dart';
import '../db/rows.dart';
import '../db/settings_repo.dart';
import '../db/users_repo.dart';
import '../services/errors.dart';
import 'bookmark_list.dart';
import 'context.dart';
import 'forms.dart';
import 'html.dart';
import 'layout.dart';

/// linkding's `views/settings.py`: the general settings, the integrations
/// page and API tokens. Importing and exporting bookmarks are in
/// `import_export.dart`.
final class SettingsViews {
  SettingsViews(this.web);

  final Web web;

  Executor get _db => web.database.connection;

  /// `/settings` and `/settings/general`.
  Future<Response> general(Request request) async {
    final (c, _, failure) = await _begin(request);
    if (failure != null) return failure;
    return _generalPage(c, await web.takeMessages(c), _ProfileForm.of(c));
  }

  /// `/settings/update`: the profile, the global settings, or one of the
  /// maintenance buttons.
  Future<Response> update(Request request) async {
    final (c, form, failure) = await _begin(request);
    if (failure != null) return failure;
    if (form == null) return c.redirect('/settings/general');
    final user = c.user!;

    if (form.has('update_profile')) {
      final profile = _ProfileForm.bound(form);
      if (profile.isValid) {
        await profile.save(_db, user.id);
        await web.addMessage(
          c,
          'Profile updated',
          extraTags: 'settings_success_message',
        );
        return c.redirect('/settings/general');
      }
      // Django's form has already written the valid fields into the
      // request's profile (unsaved), and the page is drawn with it.
      final shown = c.withProfile(Profile(profile.applyTo(c.profile.row)));
      final messages = [
        ...await web.takeMessages(c),
        const MessageRow(
          level: 'error',
          message: 'Profile update failed, check the form below for errors',
          extraTags: 'settings_error_message',
        ),
      ];
      return _generalPage(shown, messages, profile, status: 422);
    }
    if (form.has('update_global_settings')) {
      if (!user.isSuperuser) return forbiddenPage();
      await _saveGlobalSettings(form);
      await web.addMessage(
        c,
        'Global settings updated',
        extraTags: 'settings_success_message',
      );
    }
    if (form.has('refresh_favicons')) {
      // Favicons are not loaded by this server; like linkding without the
      // feature, nothing is scheduled.
      await web.addMessage(
        c,
        'Scheduled favicon update. This may take a while...',
        extraTags: 'settings_success_message',
      );
    }
    if (form.has('create_missing_html_snapshots')) {
      await web.addMessage(
        c,
        'No missing snapshots found.',
        extraTags: 'settings_success_message',
      );
    }
    return c.redirect('/settings/general');
  }

  /// `/settings/integrations`.
  Future<Response> integrations(Request request) async {
    final (c, _, failure) = await _begin(request);
    if (failure != null) return failure;
    final user = c.user!;
    final users = UsersRepo(_db);
    final tokens = (await users.apiTokens(user.id)).orThrow;
    final newKey = await web.popSessionValue(c, 'api_token_key');
    final newName = await web.popSessionValue(c, 'api_token_name');
    final message = _withTag(await web.takeMessages(c), 'api_success_message');
    var feedKey = (await users.feedToken(user.id)).orThrow;
    if (feedKey == null) {
      (await users.insertFeedToken(
        newTokenKey(),
        DateTime.now().toUtc(),
        user.id,
      )).orThrow;
      feedKey = (await users.feedToken(user.id)).orThrow!;
    }
    final host = request.headers['host'] ?? request.requestedUri.authority;
    final applicationUrl =
        '${request.requestedUri.scheme}://$host/bookmarks/new';
    return c.html(
      layout(
        c,
        title: 'Integrations - Linkding',
        content: _integrationsPage(
          c,
          applicationUrl: applicationUrl,
          tokens: tokens,
          newKey: newKey,
          newName: newName,
          message: message,
          feedKey: feedKey,
        ),
      ),
    );
  }

  /// `/settings/integrations/create-api-token`: the dialog, and creating
  /// the token, whose key is shown once on the integrations page.
  Future<Response> createApiToken(Request request) async {
    final (c, form, failure) = await _begin(request);
    if (failure != null) return failure;
    if (form == null) return c.html(_createTokenDialog(c));
    var name = (form['name'] ?? '').trim();
    if (name.isEmpty) name = 'API Token';
    final token = (await UsersRepo(_db).insertApiToken(
      newTokenKey(),
      name,
      DateTime.now().toUtc(),
      c.user!.id,
    )).orThrow;
    await web.setSessionValue(c, 'api_token_key', token.key);
    await web.setSessionValue(c, 'api_token_name', token.name);
    await web.addMessage(
      c,
      'API token "${token.name}" created successfully',
      extraTags: 'api_success_message',
    );
    return c.redirect('/settings/integrations');
  }

  /// `/settings/integrations/delete-api-token`.
  Future<Response> deleteApiToken(Request request) async {
    final (c, form, failure) = await _begin(request);
    if (failure != null) return failure;
    if (form != null) {
      final user = c.user!;
      final id = int.tryParse(form['token_id']?.trim() ?? '');
      final tokens = (await UsersRepo(_db).apiTokens(user.id)).orThrow;
      final token = tokens.where((t) => t.id == id).firstOrNull;
      if (token == null) return notFoundPage();
      (await UsersRepo(_db).deleteApiToken(token.id, user.id)).orThrow;
      await web.addMessage(
        c,
        'API token "${token.name}" has been deleted.',
        extraTags: 'api_success_message',
      );
    }
    return c.redirect('/settings/integrations');
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

  static String? _withTag(List<MessageRow> messages, String tag) =>
      messages.where((m) => m.extraTags == tag).firstOrNull?.message;

  /// `update_global_settings`: saved when valid; the page reports it saved
  /// either way, as linkding does.
  Future<void> _saveGlobalSettings(FormData form) async {
    final landingPage = form['landing_page'] ?? '';
    if (!const {'login', 'shared_bookmarks'}.contains(landingPage)) return;
    final guest = form['guest_profile_user'] ?? '';
    int? guestId;
    if (guest.isNotEmpty) {
      guestId = int.tryParse(guest.trim());
      final users = (await UsersRepo(_db).allUsers()).orThrow;
      if (!users.any((u) => u.id == guestId)) return;
    }
    final settings = (await SettingsRepo(_db).global()).orThrow!;
    (await SettingsRepo(_db).updateGlobal(
      settings.id,
      landingPage,
      guestId,
      checkboxValue(form['enable_link_prefetch']),
    )).orThrow;
  }

  Future<Response> _generalPage(
    PageContext c,
    List<MessageRow> messages,
    _ProfileForm form, {
    int status = 200,
  }) async {
    final success = _withTag(messages, 'settings_success_message');
    final error = _withTag(messages, 'settings_error_message');
    final global = c.user!.isSuperuser ? await _globalSettingsSection(c) : '';
    return c.html(
      layout(
        c,
        title: 'Settings - Linkding',
        content: _generalContent(
          c,
          form,
          success: success,
          error: error,
          global: global,
          version: await _versionInfo(),
        ),
      ),
      status: status,
    );
  }

  Future<String> _globalSettingsSection(PageContext c) async {
    final settings = c.settings;
    final users = (await UsersRepo(_db).allUsers()).orThrow;
    const classes = 'width-25 width-sm-100';
    return '''
      <section aria-labelledby="global-settings-heading">
        <h2 id="global-settings-heading">Global settings</h2>
        <form action="/settings/update"
              method="post"
              novalidate
              data-turbo="false">
          ${c.csrfInput}
          <div class="form-group">
            ${fieldLabel('landing_page', 'Landing page')}
            ${_select('landing_page', const [('login', 'Login'), ('shared_bookmarks', 'Shared Bookmarks')], settings.landingPage, fieldAttributes('landing_page', widget: const {'class': 'form-select'}, required: true, requiredAttribute: false, hasHelp: true, extra: const {'class': classes}))}
            ${fieldHelp('landing_page', '''
              The page that unauthenticated users are redirected to when accessing the root URL.
            ''')}
          </div>
          <div class="form-group">
            ${fieldLabel('guest_profile_user', 'Guest user profile')}
            ${_select('guest_profile_user', [('', 'Standard profile'), for (final u in users) ('${u.id}', u.username)], '${settings.guestProfileUserId ?? ''}', fieldAttributes('guest_profile_user', widget: const {'class': 'form-select'}, hasHelp: true, extra: const {'class': classes}))}
            ${fieldHelp('guest_profile_user', '''
              The user profile to use for users that are not logged in. This will affect how publicly shared bookmarks
              are displayed regarding theme, bookmark list settings, etc. You can either use your own profile or create
              a dedicated user for this purpose. By default, a standard profile with fixed settings is used.
            ''')}
          </div>
          <div class="form-group">
            ${checkboxField('enable_link_prefetch', settings.enableLinkPrefetch, 'Enable prefetching links on hover', fieldAttributes('enable_link_prefetch', hasHelp: true))}
            ${fieldHelp('enable_link_prefetch', '''
              Prefetches internal links when hovering over them. This can improve the perceived performance when
              navigating application, but also increases the load on the server as well as bandwidth usage.
            ''')}
          </div>
          <div class="form-group">
            <input type="submit"
                   name="update_global_settings"
                   value="Save"
                   class="btn btn-primary btn-wide mt-2">
          </div>
        </form>
      </section>''';
  }

  String _generalContent(
    PageContext c,
    _ProfileForm f, {
    required String? success,
    required String? error,
    required String global,
    required String version,
  }) {
    final saved = c.profile.row;
    String select(String name, String label, String help) =>
        '''
        <div class="form-group">
          ${fieldLabel(name, label)}
          ${_select(name, _choices[name]!, f.raw[name], f.attributes(name, widget: const {'class': 'form-select'}, required: true, requiredAttribute: false, hasHelp: true, extra: const {'class': 'width-25 width-sm-100'}))}
          ${fieldHelp(name, help)}
        </div>''';
    String check(String name, String label, {String? help}) {
      final box = checkboxField(
        name,
        f.checked(name),
        label,
        f.attributes(name, hasHelp: help != null),
      );
      return help == null ? box : '$box\n          ${fieldHelp(name, help)}';
    }

    String group(String inner) =>
        '''
        <div class="form-group">
          $inner
        </div>''';
    String textarea(String name, String label, String help) {
      final value = f.raw[name];
      return '''
        <div class="form-group">
          <details ${(value ?? '').isNotEmpty ? 'open' : ''}>
            <summary>
              <span class="form-label d-inline-block">$label</span>
            </summary>
            <label for="id_$name"
                   class="text-assistive">$label</label>
            <div>${textareaField(name, value, f.attributes(name, widget: const {'cols': '40', 'rows': '10', 'class': 'form-input'}, hasHelp: true, extra: const {'class': 'monospace', 'rows': '6'}))}</div>
          </details>
          ${fieldHelp(name, help)}
        </div>''';
    }

    String number(String name, String label, String help, {String? min}) =>
        '''
        <div class="${name == 'bookmark_description_max_lines' ? 'form-group ${saved.bookmarkDescriptionDisplay == 'inline' ? 'd-hide' : ''}' : 'form-group'}">
          ${fieldLabel(name, label)}
          ${inputField('number', name, f.raw[name], f.attributes(name, widget: const {'class': 'form-input'}, required: true, hasHelp: true, extra: {'class': 'width-25 width-sm-100', 'min': ?min}))}
          ${name == 'items_per_page' ? errorList(name, f.errors[name] ?? const [], styled: false) : ''}
          ${fieldHelp(name, help)}
        </div>''';

    return '''
  <main class="settings-page" aria-labelledby="main-heading">
    <h1 id="main-heading">Settings</h1>
    ${success == null ? '' : '<div class="toast toast-success mb-4">${e(success)}</div>'}
    ${error == null ? '' : '<div class="toast toast-error mb-4">${e(error)}</div>'}
    <section aria-labelledby="profile-heading">
      <h2 id="profile-heading">Profile</h2>
      <p>
        <a href="/change-password/">Change password</a>
      </p>
      <form action="/settings/update"
            method="post"
            novalidate
            data-turbo="false">
        ${c.csrfInput}
${select('theme', 'Theme', '''
            Whether to use a light or dark theme, or automatically adjust the theme based on your system's settings.
          ''')}
${select('bookmark_date_display', 'Bookmark date format', '''
            Whether to show bookmark dates as relative (how long ago), or as absolute dates. Alternatively the date can
            be hidden.
          ''')}
${select('bookmark_description_display', 'Bookmark description', '''
            Whether to show bookmark descriptions and tags in the same line, or as separate blocks.
          ''')}
${number('bookmark_description_max_lines', 'Bookmark description max lines', '''
            Limits the number of lines that are displayed for the bookmark description.
          ''')}
${group(check('display_url', 'Show bookmark URL', help: '''
            When enabled, this setting displays the bookmark URL below the title.
          '''))}
${group(check('permanent_notes', 'Show notes permanently', help: '''
            Whether to show bookmark notes permanently, without having to toggle them individually.
            Alternatively the keyboard shortcut <code>e</code> can be used to temporarily show all notes.
          '''))}
        <div class="form-group">
          <span class="form-label">Bookmark actions</span>
          ${check('display_view_bookmark_action', 'View')}
          ${check('display_edit_bookmark_action', 'Edit')}
          ${check('display_archive_bookmark_action', 'Archive')}
          ${check('display_remove_bookmark_action', 'Remove')}
          <div class="form-input-hint">Which actions to display for each bookmark.</div>
        </div>
${select('bookmark_link_target', 'Open bookmarks in', '''
            Whether to open bookmarks a new page or in the same page.
          ''')}
${number('items_per_page', 'Items per page', '''
            The number of bookmarks to display per page.
          ''', min: '10')}
${group(check('sticky_pagination', 'Sticky pagination', help: '''
            When enabled, the pagination controls will stick to the bottom of the screen, so that they are always
            visible without having to scroll to the end of the page first.
          '''))}
${group(check('collapse_side_panel', 'Collapse side panel', help: '''
            When enabled, the tags side panel will be collapsed by default to give more space to the bookmark list.
            Instead, the tags are shown in an expandable drawer.
          '''))}
${group(check('hide_bundles', 'Hide bundles', help: '''
            Allows to hide the bundles in the side panel if you don't intend to use them.
          '''))}
${select('tag_search', 'Tag search', '''
            In strict mode, tags must be prefixed with a hash character (#).
            In lax mode, tags can also be searched without the hash character.
            Note that tags without the hash character are indistinguishable from search terms, which means the search
            result will also include bookmarks where a search term matches otherwise.
          ''')}
${group(check('legacy_search', 'Enable legacy search', help: '''
            Since version 1.44.0, linkding has a new search engine that supports logical expressions (and, or, not).
            If you run into any issues with the new search, you can enable this option to temporarily switch back to the old search.
            Please report any issues you encounter with the new search on <a href="https://github.com/sissbruecker/linkding/issues"
    target="_blank">GitHub</a> so they can be addressed.
            This option will be removed in a future version.
          '''))}
${select('tag_grouping', 'Tag grouping', '''
            In alphabetical mode, tags will be grouped by the first letter.
            If disabled, tags will not be grouped.
          ''')}
${textarea('auto_tagging_rules', 'Auto Tagging', '''
            Automatically adds tags to bookmarks based on predefined rules.
            Each line is a single rule that maps a URL to one or more tags. For example:
            <pre>youtube.com video
reddit.com/r/Music music reddit</pre>
          ''')}
${group(check('enable_favicons', 'Enable Favicons', help: '''
            Automatically loads favicons for bookmarked websites and displays them next to each bookmark.
            Enabling this feature automatically downloads all missing favicons.
            By default, this feature uses a <b>Google service</b> to download favicons.
            If you don't want to use this service, check the
            <a href="https://linkding.link/options/#ld_favicon_provider"
               target="_blank">options documentation</a> on how to configure a custom favicon provider.
            Icons are downloaded in the background, and it may take a while for them to show up.
          '''))}
${group(check('enable_preview_images', 'Enable Preview Images', help: '''
            Automatically loads preview images for bookmarked websites and displays them next to each bookmark.
            Enabling this feature automatically downloads all missing preview images.
          '''))}
${select('web_archive_integration', 'Internet Archive integration', '''
            Enabling this feature will automatically create snapshots of bookmarked websites on the
            <a href="https://web.archive.org/" target="_blank" rel="noopener">Internet Archive Wayback Machine</a>.
            This allows to preserve, and later access the website as it was at the point in time it was bookmarked, in
            case it goes offline or its content is modified.
            Please consider donating to the <a href="https://archive.org/donate" target="_blank" rel="noopener">Internet Archive</a> if you make use of this feature.
          ''')}
${group(check('enable_sharing', 'Enable bookmark sharing', help: '''
            Allows to share bookmarks with other users, and to view shared bookmarks.
            Disabling this feature will hide all previously shared bookmarks from other users.
          '''))}
${group(check('enable_public_sharing', 'Enable public bookmark sharing', help: '''
            Makes shared bookmarks publicly accessible, without requiring a login.
            That means that anyone with a link to this instance can view shared bookmarks via the <a href="/bookmarks/shared">shared bookmarks page</a>.
          '''))}
${group(check('default_mark_unread', 'Create bookmarks as unread by default', help: '''
            Sets the default state for the "Mark as unread" option when creating a new bookmark.
            Setting this option will make all new bookmarks default to unread.
            This can be overridden when creating each new bookmark.
          '''))}
${group(check('default_mark_shared', 'Create bookmarks as shared by default', help: '''
            Sets the default state for the "Share" option when creating a new bookmark.
            Setting this option will make all new bookmarks default to shared.
            This can be overridden when creating each new bookmark.
          '''))}
${textarea('custom_css', 'Custom CSS', '''
            Allows to add custom CSS to the page.
          ''')}
        <div class="form-group">
          <input type="submit"
                 name="update_profile"
                 value="Save"
                 class="btn btn-primary btn-wide mt-2">
        </div>
      </form>
    </section>
$global
    <section aria-labelledby="import-heading">
      <h2 id="import-heading">Import</h2>
      <p>
        Import bookmarks and tags in the Netscape HTML format. This will execute a sync where new bookmarks are
        added and existing ones are updated.
      </p>
      <form method="post"
            enctype="multipart/form-data"
            action="/settings/import">
        ${c.csrfInput}
        <div class="form-group">
          <label for="import_map_private_flag" class="form-checkbox">
            <input type="checkbox"
                   id="import_map_private_flag"
                   name="map_private_flag"
                   aria-describedby="import_map_private_flag_help">
            <i class="form-icon"></i> Import public bookmarks as shared
          </label>
          <div id="import_map_private_flag_help" class="form-input-hint">
            When importing bookmarks from a service that supports marking bookmarks as public or private (using the
            <code>PRIVATE</code> attribute), enabling this option will import all bookmarks that are marked as not
            private as shared bookmarks.
            Otherwise, all bookmarks will be imported as private bookmarks.
          </div>
        </div>
        <div class="form-group">
          <div class="input-group width-75 width-md-100">
            <input class="form-input" type="file" name="import_file">
            <input type="submit" class="input-group-btn btn btn-primary" value="Upload">
          </div>
        </div>
      </form>
    </section>
    <section aria-labelledby="export-heading">
      <h2 id="export-heading">Export</h2>
      <p>Export all bookmarks in Netscape HTML format.</p>
      <a class="btn btn-primary"
         target="_blank"
         href="/settings/export">Download (.html)</a>
    </section>
    <section class="about" aria-labelledby="about-heading">
      <h2 id="about-heading">About</h2>
      <table class="table">
        <tbody>
          <tr>
            <td>Version</td>
            <td>${e(version)}</td>
          </tr>
          <tr>
            <td style="vertical-align: top">Links</td>
            <td>
              <div class="d-flex flex-column gap-2">
                <a href="https://github.com/sissbruecker/linkding/" target="_blank">GitHub</a>
                <a href="https://linkding.link/" target="_blank">Documentation</a>
                <a href="https://github.com/sissbruecker/linkding/blob/master/CHANGELOG.md"
                   target="_blank">Changelog</a>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </section>
  </main>
  <script>$_generalScript</script>''';
  }

  String _integrationsPage(
    PageContext c, {
    required String applicationUrl,
    required List<ApiTokenRow> tokens,
    required String? newKey,
    required String? newName,
    required String? message,
    required String feedKey,
  }) {
    final newToken = newKey != null && newName != null
        ? '''
        <div class="mt-4 mb-6">
          <p class="mb-2">
            <strong>Copy this token now, it will only be shown once:</strong>
          </p>
          <label class="text-assistive" for="new-token-key">New token key</label>
          <div class="input-group">
            <input class="form-input"
                   value="${e(newKey)}"
                   readonly
                   id="new-token-key">
            <button id="copy-new-token-key" class="btn input-group-btn" type="button">Copy</button>
          </div>
        </div>'''
        : '';
    final table = tokens.isEmpty
        ? ''
        : '''
        <form method="post"
              action="/settings/integrations/delete-api-token"
              data-turbo-frame="api-section">
          <table class="table crud-table mb-6">
            <thead>
              <tr>
                <th>Name</th>
                <th>Created</th>
                <th class="actions">
                  <span class="text-assistive">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody>
${[for (final t in tokens) '''
                <tr>
                  <td>${e(t.name)}</td>
                  <td>${_tokenDate(t.created)}</td>
                  <td class="actions">
                    ${c.csrfInput}
                    <button data-confirm
                            name="token_id"
                            value="${t.id}"
                            type="submit"
                            class="btn btn-link">Delete</button>
                  </td>
                </tr>'''].join('\n')}
            </tbody>
          </table>
        </form>''';
    final url = e(applicationUrl);
    return _integrationsTemplate
        .replaceAll('{{ application_url }}', url)
        .replaceFirst('{{ api_section }}', '''
      ${message == null ? '' : '<div class="toast toast-success mb-2">${e(message)}</div>'}
$newToken
      <p>
        API tokens can be used to authenticate 3rd-party applications against the REST API. <strong>Please treat
        tokens as you would any other credential.</strong> Any party with access to a token can access and manage all
        your bookmarks.
      </p>
$table''')
        .replaceAll('{{ feed_key }}', feedKey);
  }

  String _createTokenDialog(PageContext c) =>
      '''
<turbo-frame id="api-modal">
<form method="post"
      action="/settings/integrations/create-api-token"
      data-turbo-frame="api-section">
  ${c.csrfInput}
  <ld-modal class="modal active"
            data-close-url="/settings/integrations"
            data-turbo-frame="api-modal">
    <div class="modal-overlay" data-close-modal></div>
    <div class="modal-container" role="dialog" aria-modal="true">
${modalHeader('Create API Token')}
      <div class="modal-body">
        <div class="form-group">
          <label class="form-label" for="token-name">Token name</label>
          <input type="text"
                 class="form-input"
                 id="token-name"
                 name="name"
                 placeholder="e.g., Browser Extension, Mobile App"
                 value="API Token"
                 maxlength="128">
          <p class="form-input-hint">A descriptive name to identify the purpose of the token</p>
        </div>
      </div>
      <div class="modal-footer d-flex justify-between">
        <button type="button" class="btn btn-wide" data-close-modal>Cancel</button>
        <button type="submit" class="btn btn-primary">Create Token</button>
      </div>
    </div>
  </ld-modal>
</form>
</turbo-frame>''';

  /// Django's `date:"M d, Y H:i"`.
  static String _tokenDate(DateTime value) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final v = value.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${months[v.month - 1]} ${two(v.day)}, ${v.year} '
        '${two(v.hour)}:${two(v.minute)}';
  }

  static ({int hour, String text})? _version;

  /// linkding's version, with the latest release from GitHub when it can be
  /// read, cached for the hour as linkding caches it.
  static Future<String> _versionInfo() async {
    final hour = DateTime.now().millisecondsSinceEpoch ~/ 3600000;
    final cached = _version;
    if (cached != null && cached.hour == hour) return cached.text;
    String? latest;
    final client = HttpClient()
      ..findProxy = HttpClient.findProxyFromEnvironment
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(
            Uri.parse(
              'https://api.github.com/repos/sissbruecker/linkding/releases/latest',
            ),
          )
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 5));
      final json = jsonDecode(body);
      if (response.statusCode == 200 &&
          json is Map &&
          json['name'] is String &&
          (json['name'] as String).isNotEmpty) {
        latest = (json['name'] as String).substring(1);
      }
    } on Object {
      // No network, or not the answer expected: the version alone.
    } finally {
      client.close(force: true);
    }
    final text = latest == null
        ? linkdingVersion
        : latest == linkdingVersion
        ? '$linkdingVersion (latest)'
        : '$linkdingVersion (latest: $latest)';
    _version = (hour: hour, text: text);
    return text;
  }
}

/// A `FormSelect` with the attributes [fieldAttributes] built.
String _select(
  String name,
  List<(String, String)> choices,
  String? selected,
  Map<String, Object> attrs,
) {
  final attributes = [
    for (final MapEntry(:key, :value) in attrs.entries)
      value == true ? ' $key' : ' $key="${e(value)}"',
  ].join();
  final options = [
    for (final (value, label) in choices)
      '  <option value="${e(value)}"${value == selected ? ' selected' : ''}>${e(label)}</option>\n',
  ].join('\n');
  return '<select name="$name"$attributes>\n$options\n</select>';
}

const _choices = {
  'theme': [('auto', 'Auto'), ('light', 'Light'), ('dark', 'Dark')],
  'bookmark_date_display': [
    ('relative', 'Relative'),
    ('absolute', 'Absolute'),
    ('hidden', 'Hidden'),
  ],
  'bookmark_description_display': [
    ('inline', 'Inline'),
    ('separate', 'Separate'),
  ],
  'bookmark_link_target': [('_blank', 'New page'), ('_self', 'Same page')],
  'web_archive_integration': [('disabled', 'Disabled'), ('enabled', 'Enabled')],
  'tag_search': [('strict', 'Strict'), ('lax', 'Lax')],
  'tag_grouping': [('alphabetical', 'Alphabetical'), ('disabled', 'Disabled')],
};

const _booleans = [
  'enable_sharing',
  'enable_public_sharing',
  'enable_favicons',
  'enable_preview_images',
  'enable_automatic_html_snapshots',
  'display_url',
  'display_view_bookmark_action',
  'display_edit_bookmark_action',
  'display_archive_bookmark_action',
  'display_remove_bookmark_action',
  'permanent_notes',
  'default_mark_unread',
  'default_mark_shared',
  'sticky_pagination',
  'collapse_side_panel',
  'hide_bundles',
  'legacy_search',
];

/// linkding's `UserProfileForm`: what the fields show, and once submitted,
/// the values to save and the errors.
final class _ProfileForm {
  _ProfileForm(this.raw, this.booleans, {this.errors = const {}});

  factory _ProfileForm.of(PageContext c) {
    final p = c.profile.row;
    return _ProfileForm(
      {
        'theme': p.theme,
        'bookmark_date_display': p.bookmarkDateDisplay,
        'bookmark_description_display': p.bookmarkDescriptionDisplay,
        'bookmark_description_max_lines': '${p.bookmarkDescriptionMaxLines}',
        'bookmark_link_target': p.bookmarkLinkTarget,
        'web_archive_integration': p.webArchiveIntegration,
        'tag_search': p.tagSearch,
        'tag_grouping': p.tagGrouping,
        'custom_css': p.customCss,
        'auto_tagging_rules': p.autoTaggingRules,
        'items_per_page': '${p.itemsPerPage}',
      },
      {
        'enable_sharing': p.enableSharing,
        'enable_public_sharing': p.enablePublicSharing,
        'enable_favicons': p.enableFavicons,
        'enable_preview_images': p.enablePreviewImages,
        'enable_automatic_html_snapshots': p.enableAutomaticHtmlSnapshots,
        'display_url': p.displayUrl,
        'display_view_bookmark_action': p.displayViewBookmarkAction,
        'display_edit_bookmark_action': p.displayEditBookmarkAction,
        'display_archive_bookmark_action': p.displayArchiveBookmarkAction,
        'display_remove_bookmark_action': p.displayRemoveBookmarkAction,
        'permanent_notes': p.permanentNotes,
        'default_mark_unread': p.defaultMarkUnread,
        'default_mark_shared': p.defaultMarkShared,
        'sticky_pagination': p.stickyPagination,
        'collapse_side_panel': p.collapseSidePanel,
        'hide_bundles': p.hideBundles,
        'legacy_search': p.legacySearch,
      },
    );
  }

  factory _ProfileForm.bound(FormData data) {
    final raw = <String, String?>{
      for (final name in [
        ..._choices.keys,
        'bookmark_description_max_lines',
        'items_per_page',
        'custom_css',
        'auto_tagging_rules',
      ])
        name: data[name],
    };
    final errors = <String, List<String>>{};
    for (final MapEntry(key: name, value: choices) in _choices.entries) {
      final value = raw[name] ?? '';
      if (value.isEmpty) {
        errors[name] = ['This field is required.'];
      } else if (!choices.any((c) => c.$1 == value)) {
        errors[name] = [
          'Select a valid choice. $value is not one of the available choices.',
        ];
      }
    }
    for (final (name, min) in const [
      ('bookmark_description_max_lines', null),
      ('items_per_page', 10),
    ]) {
      final problem = _integerError(raw[name], min);
      if (problem != null) errors[name] = [problem];
    }
    return _ProfileForm(raw, {
      for (final name in _booleans) name: checkboxValue(data[name]),
    }, errors: errors);
  }

  /// What each non-checkbox field shows: the saved value, or what was sent.
  final Map<String, String?> raw;
  final Map<String, bool> booleans;
  final Map<String, List<String>> errors;

  bool get isValid => errors.isEmpty;

  bool checked(String name) => booleans[name] ?? false;

  Map<String, Object> attributes(
    String name, {
    Map<String, Object> widget = const {},
    bool required = false,
    bool requiredAttribute = true,
    bool hasHelp = false,
    Map<String, Object> extra = const {},
  }) => fieldAttributes(
    name,
    widget: widget,
    required: required,
    requiredAttribute: requiredAttribute,
    hasHelp: hasHelp,
    errors: errors[name] ?? const [],
    extra: extra,
  );

  /// Django's `IntegerField`, then the model's limits.
  static String? _integerError(String? raw, int? min) {
    final text = (raw ?? '').trim().replaceFirst(RegExp(r'\.0*\s*$'), '');
    if (text.isEmpty) return 'This field is required.';
    final value = int.tryParse(text);
    if (value == null) return 'Enter a whole number.';
    if (min != null && value < min) {
      return 'Ensure this value is greater than or equal to $min.';
    }
    if (value < -2147483648) {
      return 'Ensure this value is greater than or equal to -2147483648.';
    }
    if (value > 2147483647) {
      return 'Ensure this value is less than or equal to 2147483647.';
    }
    return null;
  }

  /// [saved] with every field that passed its checks set to the submitted
  /// value, as Django's `construct_instance` leaves the profile of an
  /// invalid form. The CSS hash is only computed on saving.
  ProfileRow applyTo(ProfileRow saved) {
    String choice(String name, String current) =>
        errors.containsKey(name) ? current : raw[name]!;
    int number(String name, int current) =>
        errors.containsKey(name) ? current : _int(name);
    return ProfileRow(
      id: saved.id,
      userId: saved.userId,
      theme: choice('theme', saved.theme),
      bookmarkDateDisplay: choice(
        'bookmark_date_display',
        saved.bookmarkDateDisplay,
      ),
      bookmarkDescriptionDisplay: choice(
        'bookmark_description_display',
        saved.bookmarkDescriptionDisplay,
      ),
      bookmarkDescriptionMaxLines: number(
        'bookmark_description_max_lines',
        saved.bookmarkDescriptionMaxLines,
      ),
      bookmarkLinkTarget: choice(
        'bookmark_link_target',
        saved.bookmarkLinkTarget,
      ),
      webArchiveIntegration: choice(
        'web_archive_integration',
        saved.webArchiveIntegration,
      ),
      tagSearch: choice('tag_search', saved.tagSearch),
      tagGrouping: choice('tag_grouping', saved.tagGrouping),
      enableSharing: checked('enable_sharing'),
      enablePublicSharing: checked('enable_public_sharing'),
      enableFavicons: checked('enable_favicons'),
      enablePreviewImages: checked('enable_preview_images'),
      displayUrl: checked('display_url'),
      displayViewBookmarkAction: checked('display_view_bookmark_action'),
      displayEditBookmarkAction: checked('display_edit_bookmark_action'),
      displayArchiveBookmarkAction: checked('display_archive_bookmark_action'),
      displayRemoveBookmarkAction: checked('display_remove_bookmark_action'),
      permanentNotes: checked('permanent_notes'),
      customCss: (raw['custom_css'] ?? '').trim(),
      customCssHash: saved.customCssHash,
      autoTaggingRules: (raw['auto_tagging_rules'] ?? '').trim(),
      searchPreferencesJson: saved.searchPreferencesJson,
      enableAutomaticHtmlSnapshots: checked('enable_automatic_html_snapshots'),
      defaultMarkUnread: checked('default_mark_unread'),
      defaultMarkShared: checked('default_mark_shared'),
      itemsPerPage: number('items_per_page', saved.itemsPerPage),
      stickyPagination: checked('sticky_pagination'),
      collapseSidePanel: checked('collapse_side_panel'),
      hideBundles: checked('hide_bundles'),
      legacySearch: checked('legacy_search'),
    );
  }

  int _int(String name) =>
      int.parse(raw[name]!.trim().replaceFirst(RegExp(r'\.0*\s*$'), ''));

  Future<void> save(Executor db, int userId) async {
    final css = (raw['custom_css'] ?? '').trim();
    (await UsersRepo(db).updateProfile(
      userId,
      raw['theme']!,
      raw['bookmark_date_display']!,
      raw['bookmark_description_display']!,
      _int('bookmark_description_max_lines'),
      raw['bookmark_link_target']!,
      raw['web_archive_integration']!,
      raw['tag_search']!,
      raw['tag_grouping']!,
      checked('enable_sharing'),
      checked('enable_public_sharing'),
      checked('enable_favicons'),
      checked('enable_preview_images'),
      checked('display_url'),
      checked('display_view_bookmark_action'),
      checked('display_edit_bookmark_action'),
      checked('display_archive_bookmark_action'),
      checked('display_remove_bookmark_action'),
      checked('permanent_notes'),
      css,
      css.isEmpty ? '' : md5.convert(utf8.encode(css)).toString(),
      (raw['auto_tagging_rules'] ?? '').trim(),
      checked('enable_automatic_html_snapshots'),
      checked('default_mark_unread'),
      checked('default_mark_shared'),
      _int('items_per_page'),
      checked('sticky_pagination'),
      checked('collapse_side_panel'),
      checked('hide_bundles'),
      checked('legacy_search'),
    )).orThrow;
  }
}

/// linkding's script for `settings/general.html`, verbatim.
const _generalScript = r'''
    (function init() {
      const enableSharing = document.getElementById("id_enable_sharing");
      const enablePublicSharing = document.getElementById("id_enable_public_sharing");
      const defaultMarkShared = document.getElementById("id_default_mark_shared");
      const bookmarkDescriptionDisplay = document.getElementById("id_bookmark_description_display");
      const bookmarkDescriptionMaxLines = document.getElementById("id_bookmark_description_max_lines");

      // Automatically disable public bookmark sharing and default shared option if bookmark sharing is disabled
      function updateSharingOptions() {
        if (enableSharing.checked) {
          enablePublicSharing.disabled = false;
          defaultMarkShared.disabled = false;
        } else {
          enablePublicSharing.disabled = true;
          enablePublicSharing.checked = false;
          defaultMarkShared.disabled = true;
          defaultMarkShared.checked = false;
        }
      }

      updateSharingOptions();
      enableSharing.addEventListener("change", updateSharingOptions);

      // Automatically hide the bookmark description max lines input if the description display is set to inline
      function updateBookmarkDescriptionMaxLines() {
        if (bookmarkDescriptionDisplay.value === "inline") {
          bookmarkDescriptionMaxLines.closest(".form-group").classList.add("d-hide");
        } else {
          bookmarkDescriptionMaxLines.closest(".form-group").classList.remove("d-hide");
        }
      }

      updateBookmarkDescriptionMaxLines();
      bookmarkDescriptionDisplay.addEventListener("change", updateBookmarkDescriptionMaxLines);
    })();
  ''';

/// `settings/integrations.html`, with `{{ application_url }}`,
/// `{{ api_section }}` and `{{ feed_key }}` filled in per request.
const _integrationsTemplate = r'''
  <main class="settings-page" aria-labelledby="main-heading">
    <h1 id="main-heading">Integrations</h1>
    <section aria-labelledby="browser-extension-heading">
      <h2 id="browser-extension-heading">Browser Extension</h2>
      <p>
        The browser extension allows you to quickly add new bookmarks without leaving the page that you are on. The
        extension is available in the official extension stores for:
      </p>
      <ul>
        <li>
          <a href="https://addons.mozilla.org/firefox/addon/linkding-extension/"
             target="_blank">Firefox</a>
        </li>
        <li>
          <a href="https://chrome.google.com/webstore/detail/linkding-extension/beakmhbijpdhipnjhnclmhgjlddhidpe"
             target="_blank">Chrome</a>
        </li>
      </ul>
      <p>
        The extension is <a href="https://github.com/sissbruecker/linkding-extension"
    target="_blank">open source</a>
        as well, which enables you to build and manually load it into any browser that supports Chrome extensions.
      </p>
      <h2>Bookmarklet</h2>
      <p>
        The bookmarklet is an alternative, cross-browser way to quickly add new bookmarks without opening the linkding
        application first. Here's how it works:
      </p>
      <ul>
        <li>
          Choose your preferred method for detecting website titles and descriptions below (<a href="https://linkding.link/troubleshooting/#automatically-detected-title-and-description-are-incorrect"
   target="_blank">Help</a>)
        </li>
        <li>Drag the bookmarklet below into your browser's bookmark bar / toolbar</li>
        <li>Open the website that you want to bookmark</li>
        <li>Click the bookmarklet in your browser's toolbar</li>
        <li>linkding opens in a new window or tab and allows you to add a bookmark for the site</li>
        <li>After saving the bookmark, the linkding window closes, and you are back on your website</li>
      </ul>
      <div class="form-group radio-group"
           role="radiogroup"
           aria-labelledby="detection-method-label">
        <p id="detection-method-label">Choose your preferred bookmarklet:</p>
        <label for="detection-method-server" class="form-radio">
          <input id="detection-method-server"
                 type="radio"
                 name="bookmarklet-type"
                 value="server"
                 checked>
          <i class="form-icon"></i>
          Detect title and description on the server
        </label>
        <label for="detection-method-client" class="form-radio">
          <input id="detection-method-client"
                 type="radio"
                 name="bookmarklet-type"
                 value="client">
          <i class="form-icon"></i>
          Detect title and description in the browser
        </label>
      </div>
      <div class="bookmarklet-container">
        <a id="bookmarklet-server"
           href="javascript: (function () {
  const bookmarkUrl = window.location;

  let applicationUrl = '{{ application_url }}';
  applicationUrl += '?url=' + encodeURIComponent(bookmarkUrl);
  applicationUrl += '&auto_close';

  window.open(applicationUrl);
})();
"
           data-turbo="false"
           class="btn btn-primary">📎 Add bookmark</a>
        <a id="bookmarklet-client"
           href="javascript: (function () {
  const bookmarkUrl = window.location;
  const title =
    document.querySelector('title')?.textContent ||
    document
      .querySelector(`meta[property='og:title']`)
      ?.getAttribute('content') ||
    '';
  const description =
    document
      .querySelector(`meta[name='description']`)
      ?.getAttribute('content') ||
    document
      .querySelector(`meta[property='og:description']`)
      ?.getAttribute(`content`) ||
    '';

  let applicationUrl = '{{ application_url }}';
  applicationUrl += '?url=' + encodeURIComponent(bookmarkUrl);
  applicationUrl += '&title=' + encodeURIComponent(title);
  applicationUrl += '&description=' + encodeURIComponent(description);
  applicationUrl += '&auto_close';

  window.open(applicationUrl);
})();
"
           data-turbo="false"
           class="btn btn-primary"
           style="display: none">📎 Add bookmark</a>
      </div>
      <script>
        (function init() {
          // Bookmarklet type toggle
          const radioButtons = document.querySelectorAll('input[name="bookmarklet-type"]');
          const serverBookmarklet = document.getElementById('bookmarklet-server');
          const clientBookmarklet = document.getElementById('bookmarklet-client');

          function toggleBookmarklet() {
            const selectedValue = document.querySelector('input[name="bookmarklet-type"]:checked').value;
            if (selectedValue === 'server') {
              serverBookmarklet.style.display = 'inline-block';
              clientBookmarklet.style.display = 'none';
            } else {
              serverBookmarklet.style.display = 'none';
              clientBookmarklet.style.display = 'inline-block';
            }
          }

          toggleBookmarklet();
          radioButtons.forEach(function(radio) {
            radio.addEventListener('change', toggleBookmarklet);
          });
        })();
      </script>
    </section>
    <turbo-frame id="api-section">
    <section aria-labelledby="rest-api-heading">
      <h2 id="rest-api-heading">REST API</h2>
{{ api_section }}
      <a class="btn"
         href="/settings/integrations/create-api-token"
         data-turbo-frame="api-modal">Create API token</a>
    </section>
    <turbo-frame id="api-modal"></turbo-frame>
    <script>
      (function init() {
        // Copy new token key to clipboard
        const copyButton = document.getElementById('copy-new-token-key');
        if (copyButton) {
          copyButton.addEventListener('click', () => {
            const tokenInput = document.getElementById('new-token-key');
            const tokenValue = tokenInput.value;
            navigator.clipboard.writeText(tokenValue).then(() => {
              copyButton.textContent = 'Copied!';
              setTimeout(() => {
                copyButton.textContent = 'Copy';
              }, 2000);
            }, (err) => {
              console.error('Could not copy text: ', err);
            });
          });
        }
      })();
    </script>
    </turbo-frame>
    <section aria-labelledby="rss-feeds-heading">
      <h2 id="rss-feeds-heading">RSS Feeds</h2>
      <p>The following URLs provide RSS feeds for your bookmarks:</p>
      <ul style="list-style-position: outside;">
        <li>
          <a target="_blank" href="/feeds/{{ feed_key }}/all">All bookmarks</a>
        </li>
        <li>
          <a target="_blank" href="/feeds/{{ feed_key }}/unread">Unread bookmarks</a>
        </li>
        <li>
          <a target="_blank" href="/feeds/{{ feed_key }}/shared">Shared bookmarks</a>
        </li>
        <li>
          <a target="_blank" href="/feeds/shared">Public shared bookmarks</a>
          <br>
          <span class="text-small text-secondary">The public shared feed does not contain an authentication token and can be shared with other people. Only shows shared bookmarks from users who have explicitly enabled public sharing.</span>
        </li>
      </ul>
      <p>Feed URLs support the following URL parameters:</p>
      <ul style="list-style-position: outside;">
        <li>
          A <code>limit</code> parameter for specifying the maximum number of bookmarks to include in the feed. By
          default, only the latest 100 matching bookmarks are included.
        </li>
        <li>
          A <code>q</code> URL parameter for specifying a search query. You can get an example by doing a search in
          the bookmarks view and then copying the parameter from the URL.
        </li>
        <li>
          An <code>unread</code> parameter for filtering for unread or read bookmarks. Use <code>yes</code> for unread
          bookmarks and <code>no</code> for read bookmarks.
        </li>
        <li>
          A <code>shared</code> parameter for filtering for shared or unshared bookmarks. Use <code>yes</code> for
          shared bookmarks and <code>no</code> for unshared bookmarks.
        </li>
        <li>
          A <code>user</code> parameter for filtering bookmarks by user name. Only applies to the shared bookmark feeds.
        </li>
      </ul>
      <p>
        <strong>Please note that these URLs include an authentication token that should be treated like any other
        credential.</strong>
        Any party with access to these URLs can read all your bookmarks.
        If you think that a URL was compromised you can delete the feed token for your user in the <a target="_blank"
    href="/admin/bookmarks/feedtoken/">admin panel</a>.
        After deleting the feed token, new URLs will be generated when you reload this settings page.
      </p>
    </section>
  </main>
''';
