import 'dart:io';

import 'package:dust_server/server.dart';

import '../auth/password_validation.dart';
import '../auth/sessions.dart';
import '../config.dart';
import '../core/profile.dart';
import '../db/database.dart';
import '../db/rows.dart';
import '../db/settings_repo.dart';
import '../db/users_repo.dart';
import '../services/assets.dart';
import '../services/bookmarks.dart';
import '../services/errors.dart';
import '../services/website_loader.dart';
import 'html.dart';

/// What every page handler needs: the services, and the request's user,
/// profile, settings and CSRF token.
final class Web {
  Web({
    required this.database,
    required this.config,
    required this.sessions,
    required this.bookmarks,
    required this.assets,
    required this.metadata,
  });

  final LinkdingDatabase database;
  final ServerConfig config;
  final Sessions sessions;
  final BookmarkService bookmarks;
  final AssetService assets;
  final WebsiteMetadataLoader metadata;

  /// The password rules, with Django's list of common passwords.
  late final passwords = PasswordValidator.fromFile(
    '${config.webRoot}/data/common-passwords.txt.gz',
  );

  /// Queues a one-time message for the visitor's next page that shows
  /// messages: Django's `messages.success` and friends.
  Future<void> addMessage(
    PageContext c,
    String message, {
    String level = 'success',
    String extraTags = '',
  }) async {
    final key = requestCookies(c.request)[sessionCookie];
    if (key == null || !c.isAuthenticated) return;
    (await SettingsRepo(
      database.connection,
    ).addMessage(key, level, message, extraTags)).orThrow;
  }

  /// The visitor's waiting messages, which are shown once.
  Future<List<MessageRow>> takeMessages(PageContext c) async {
    final key = requestCookies(c.request)[sessionCookie];
    if (key == null || !c.isAuthenticated) return const [];
    return (await SettingsRepo(database.connection).takeMessages(key)).orThrow;
  }

  /// Keeps [value] in the visitor's session for a later request.
  Future<void> setSessionValue(PageContext c, String name, String value) async {
    final key = requestCookies(c.request)[sessionCookie];
    if (key == null || !c.isAuthenticated) return;
    (await SettingsRepo(
      database.connection,
    ).setSessionValue(key, name, value)).orThrow;
  }

  /// A value kept in the visitor's session, removed as it is read.
  Future<String?> popSessionValue(PageContext c, String name) async {
    final key = requestCookies(c.request)[sessionCookie];
    if (key == null || !c.isAuthenticated) return null;
    return (await SettingsRepo(
      database.connection,
    ).popSessionValue(key, name)).orThrow;
  }

  /// Everything a page needs to know about who is asking.
  Future<PageContext> context(Request request) async {
    final user = await sessions.user(request);
    final db = database.connection;
    final global = (await SettingsRepo(db).global()).orThrow!;
    // Visitors see the pages with the guest profile's preferences when one
    // is configured, otherwise with the defaults and favicons on.
    final profileOf = user?.id ?? global.guestProfileUserId;
    final row = profileOf == null
        ? null
        : (await UsersRepo(db).profile(profileOf)).orThrow;
    final toasts = user == null
        ? const <ToastRow>[]
        : (await SettingsRepo(db).toasts(user.id)).orThrow;
    return PageContext(
      request: request,
      user: user,
      profile: Profile(row ?? standardProfile),
      settings: global,
      toasts: toasts,
      csrf: Sessions.csrfToken(request),
    );
  }
}

/// One request, as the page templates see it.
final class PageContext {
  PageContext({
    required this.request,
    required this.user,
    required this.profile,
    required this.settings,
    required this.toasts,
    required this._csrf,
  });

  final Request request;
  final UserRow? user;

  /// The user's preferences, or the guest profile's for visitors:
  /// `request.user_profile`.
  final Profile profile;
  final GlobalSettingsRow settings;
  final List<ToastRow> toasts;
  final ({String token, String? setCookie}) _csrf;

  late final String _maskedCsrf = maskCsrf(_csrf.token);

  bool get isAuthenticated => user != null;

  /// This request drawn with [profile] instead of the saved one.
  PageContext withProfile(Profile profile) => PageContext(
    request: request,
    user: user,
    profile: profile,
    settings: settings,
    toasts: toasts,
    csrf: _csrf,
  );

  /// The hidden form field Django's `{% csrf_token %}` renders.
  String get csrfInput =>
      '<input type="hidden" name="csrfmiddlewaretoken" value="$_maskedCsrf">';

  String get csrfToken => _maskedCsrf;

  /// `request.path`.
  String get path => request.requestedUri.path;

  /// `request.get_full_path()`.
  String get fullPath {
    final uri = request.requestedUri;
    return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  }

  Map<String, String> get query => request.requestedUri.queryParameters;

  /// The scheme and host the visitor asked for, as Django's
  /// `build_absolute_uri` starts an absolute URL.
  String get baseUrl {
    final uri = request.requestedUri;
    return '${uri.scheme}://${request.headers['host'] ?? uri.authority}';
  }

  /// An HTML response for this request, setting the CSRF cookie when the
  /// browser did not have one yet.
  Response html(
    String body, {
    int status = 200,
    Map<String, Object> headers = const {},
  }) => Response(
    status,
    body: body,
    headers: {
      HttpHeaders.contentTypeHeader: 'text/html; charset=utf-8',
      'vary': 'Cookie',
      'x-frame-options': 'DENY',
      'referrer-policy': 'same-origin',
      'set-cookie': ?_csrf.setCookie,
      ...headers,
    },
  );

  /// A response that is not a page, with the headers Django's middleware
  /// adds to every response.
  Response text(
    String body, {
    required String contentType,
    int status = 200,
    Map<String, Object> headers = const {},
  }) => Response(
    status,
    body: body,
    headers: {
      HttpHeaders.contentTypeHeader: contentType,
      'vary': 'Cookie',
      'x-frame-options': 'DENY',
      'referrer-policy': 'same-origin',
      ...headers,
    },
  );

  /// A redirect, keeping the CSRF cookie in step.
  Response redirect(String location, {List<String> cookies = const []}) =>
      Response(
        302,
        headers: {
          'location': location,
          'content-type': 'text/html; charset=utf-8',
          'set-cookie': [?_csrf.setCookie, ...cookies],
        },
      );
}

/// The preferences of a visitor when no guest profile is set: a fresh
/// `UserProfile` with favicons enabled.
const standardProfile = ProfileRow(
  id: 0,
  userId: 0,
  theme: 'auto',
  bookmarkDateDisplay: 'relative',
  bookmarkDescriptionDisplay: 'inline',
  bookmarkDescriptionMaxLines: 1,
  bookmarkLinkTarget: '_blank',
  webArchiveIntegration: 'disabled',
  tagSearch: 'strict',
  tagGrouping: 'alphabetical',
  enableSharing: false,
  enablePublicSharing: false,
  enableFavicons: true,
  enablePreviewImages: false,
  displayUrl: false,
  displayViewBookmarkAction: true,
  displayEditBookmarkAction: true,
  displayArchiveBookmarkAction: true,
  displayRemoveBookmarkAction: true,
  permanentNotes: false,
  customCss: '',
  customCssHash: '',
  autoTaggingRules: '',
  searchPreferencesJson: '{}',
  enableAutomaticHtmlSnapshots: true,
  defaultMarkUnread: false,
  defaultMarkShared: false,
  itemsPerPage: 30,
  stickyPagination: false,
  collapseSidePanel: false,
  hideBundles: false,
  legacySearch: false,
);

/// Django's 403 page for a failed CSRF check.
Response csrfFailurePage(PageContext c, String reason) => c.html(
  '<!DOCTYPE html><html lang="en"><head><title>403 Forbidden</title></head>'
  '<body><h1>Forbidden <span>(403)</span></h1><p>CSRF verification failed. '
  'Request aborted.</p><p>Reason given for failure: ${e(reason)}</p></body></html>',
  status: 403,
);

/// Django's page for a path nothing serves, or an object that is not there
/// or not the visitor's.
Response notFoundPage() => Response(
  404,
  body:
      '\n<!doctype html>\n<html lang="en">\n<head>\n  <title>Not Found</title>\n'
      '</head>\n<body>\n  <h1>Not Found</h1><p>The requested resource was not '
      'found on this server.</p>\n</body>\n</html>\n',
  headers: {'content-type': 'text/html; charset=utf-8'},
);

/// The media type of a Turbo Stream response.
const turboStreamType = 'text/vnd.turbo-stream.html';

/// linkding's `turbo.update`: [content] as the new inside of [target].
String turboUpdate(String target, String content, {String method = ''}) =>
    '<turbo-stream action="update"${method.isEmpty ? '' : ' method="$method"'} '
    'target="$target"><template>$content</template></turbo-stream>';

/// linkding's `turbo.replace`: [content] in place of [target].
String turboReplace(String target, String content, {String method = ''}) =>
    '<turbo-stream action="replace"${method.isEmpty ? '' : ' method="$method"'} '
    'target="$target"><template>$content</template></turbo-stream>';

/// linkding's `turbo.stream`: several stream elements in one response.
Response turboStream(PageContext c, List<String> streams) =>
    c.html(streams.join('\n'), headers: {'content-type': turboStreamType});

/// Django's page for an error in the application: where linkding fails with
/// an exception, the clone answers the same way.
Response serverErrorPage() => Response(
  500,
  body:
      '\n<!doctype html>\n<html lang="en">\n<head>\n  <title>Server Error (500)'
      '</title>\n</head>\n<body>\n  <h1>Server Error (500)</h1><p></p>\n'
      '</body>\n</html>\n',
  headers: {'content-type': 'text/html; charset=utf-8'},
);

/// Django's page for a request that is not allowed: `PermissionDenied`.
Response forbiddenPage() => Response(
  403,
  body:
      '\n<!doctype html>\n<html lang="en">\n<head>\n  <title>403 Forbidden</title>\n'
      '</head>\n<body>\n  <h1>403 Forbidden</h1><p></p>\n</body>\n</html>\n',
  headers: {'content-type': 'text/html; charset=utf-8'},
);

/// Django's `redirect_to_login` to linkding's `LOGIN_URL`:
/// `/login?next=<path>`, which then gains its slash.
Response redirectToLogin(PageContext c) =>
    c.redirect('/login?next=${q(c.fullPath)}');

/// `{% static %}` with linkding's cache-busting version parameter where
/// linkding uses one.
String static(String name, {bool versioned = false}) =>
    versioned ? '/static/$name?v=$linkdingVersion' : '/static/$name';
