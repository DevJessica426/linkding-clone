import 'package:dust_server/server.dart';

import '../auth/password_validation.dart';
import '../auth/passwords.dart';
import '../auth/sessions.dart';
import '../compat/form_data.dart';
import '../compat/pyurl.dart';
import '../db/users_repo.dart';
import '../services/errors.dart';
import 'context.dart';
import 'forms.dart';
import 'html.dart';
import 'layout.dart';
import 'query_params.dart';

/// Signing in and out, changing the password, and the root redirect;
/// Django's `LoginView`, `LogoutView` and `PasswordChangeView`, and
/// linkding's `root` view.
final class AuthViews {
  AuthViews(this.web);

  final Web web;

  /// `/`: to the bookmarks, or for visitors to the shared bookmarks when
  /// that is the landing page. The query is kept as linkding's
  /// `redirect_with_query` keeps it: re-encoded, with the last value of a
  /// repeated name.
  Future<Response> root(Request request) async {
    final c = await web.context(request);
    final params = QueryParams.parse(request.requestedUri.query).last;
    final encoded = urlencode([
      for (final MapEntry(:key, :value) in params.entries) (key, value),
    ]);
    final query = encoded.isEmpty ? '' : '?$encoded';
    if (!c.isAuthenticated && c.settings.landingPage == 'shared_bookmarks') {
      return c.redirect('/bookmarks/shared$query');
    }
    return c.redirect('/bookmarks$query');
  }

  Future<Response> login(Request request) async {
    final c = await web.context(request);
    if (request.method == 'POST') return _submit(request, c);
    final next = c.query['next'] ?? '';
    if (c.isAuthenticated) return c.redirect(_safeNext(next));
    return c.html(_page(c, next: next));
  }

  Future<Response> _submit(Request request, PageContext c) async {
    final form = await readFormData(request);
    final failure = Sessions.csrfFailure(request, form['csrfmiddlewaretoken']);
    if (failure != null) return csrfFailurePage(c, failure);

    final username = form['username'] ?? '';
    final password = form['password'] ?? '';
    final next = form['next'] ?? '';
    final users = UsersRepo(web.database.connection);
    final user = (await users.byUsername(username)).orThrow;
    final hasher = PasswordHasher(iterations: web.config.passwordIterations);
    final valid =
        user != null &&
        user.isActive &&
        await hasher.verify(password, user.password);
    if (!valid) {
      // 401 on a failed sign-in, as linkding answers for fail2ban.
      return c.html(
        _page(c, next: next, username: username, failed: true),
        status: 401,
      );
    }
    if (hasher.mustUpdate(user.password)) {
      (await users.setPassword(user.id, await hasher.hash(password))).orThrow;
    }
    (await users.setLastLogin(user.id, DateTime.now().toUtc())).orThrow;
    final session = await web.sessions.start(user.id);
    return c.redirect(_safeNext(next), cookies: [session]);
  }

  /// `POST /logout/`, then to the sign-in page.
  Future<Response> logout(Request request) async {
    final c = await web.context(request);
    if (request.method != 'POST') {
      return Response(405, headers: {'allow': 'POST, OPTIONS'});
    }
    final form = await readFormData(request);
    final failure = Sessions.csrfFailure(request, form['csrfmiddlewaretoken']);
    if (failure != null) return csrfFailurePage(c, failure);
    final cleared = await web.sessions.end(request);
    return c.redirect('/login', cookies: [cleared]);
  }

  /// `/change-password/`: Django's `PasswordChangeView` with linkding's
  /// error list, answering a failed change with 422 for Turbo.
  Future<Response> changePassword(Request request) async {
    final c = await web.context(request);
    FormData? form;
    if (request.method == 'POST') {
      form = await readFormData(request);
      final failure = Sessions.csrfFailure(
        request,
        form['csrfmiddlewaretoken'],
      );
      if (failure != null) return csrfFailurePage(c, failure);
    }
    if (!c.isAuthenticated) return redirectToLogin(c);
    if (form == null) return c.html(_passwordPage(c, const {}));

    final user = c.user!;
    final users = UsersRepo(web.database.connection);
    final hasher = PasswordHasher(iterations: web.config.passwordIterations);
    final errors = <String, List<String>>{
      'old_password': [],
      'new_password1': [],
      'new_password2': [],
    };
    // `CharField(strip=False)` for each field, in order.
    final cleaned = <String, String>{};
    for (final MapEntry(key: name, value: fieldErrors) in errors.entries) {
      final value = form[name] ?? '';
      if (value.isEmpty) {
        fieldErrors.add('This field is required.');
      } else if (value.contains('\x00')) {
        fieldErrors.add('Null characters are not allowed.');
      } else {
        cleaned[name] = value;
      }
    }
    // `clean_old_password`; a correct password in an outdated hash is
    // stored again, as Django's `check_password` does.
    if (cleaned['old_password'] case final old?) {
      if (await hasher.verify(old, user.password)) {
        if (hasher.mustUpdate(user.password)) {
          (await users.setPassword(user.id, await hasher.hash(old))).orThrow;
        }
      } else {
        errors['old_password']!.add(
          'Your old password was entered incorrectly. Please enter it again.',
        );
        cleaned.remove('old_password');
      }
    }
    // `SetPasswordForm.clean`: the two must match, and the second must
    // pass the password validators.
    final first = cleaned['new_password1'];
    final second = cleaned['new_password2'];
    if (first != null && second != null && first != second) {
      errors['new_password2']!.add('The two password fields didn’t match.');
      cleaned.remove('new_password2');
    }
    if (cleaned['new_password2'] case final password?) {
      errors['new_password2']!.addAll(validatePassword(password, user));
    }
    if (errors.values.any((e) => e.isNotEmpty)) {
      return c.html(_passwordPage(c, errors), status: 422);
    }

    (await users.setPassword(user.id, await hasher.hash(first!))).orThrow;
    final session = await web.sessions.keepAfterPasswordChange(
      request,
      user.id,
    );
    return c.redirect('/password-change-done/', cookies: [?session]);
  }

  /// `/password-change-done/`.
  Future<Response> passwordChangeDone(Request request) async {
    final c = await web.context(request);
    if (!c.isAuthenticated) return redirectToLogin(c);
    return c.html(
      layout(
        c,
        title: 'Password changed - Linkding',
        content: '''
  <main class="auth-page" aria-labelledby="main-heading">
    <div class="section-header">
      <h1 id="main-heading">Password Changed</h1>
    </div>
    <p class="text-success">Your password was changed successfully.</p>
  </main>''',
      ),
    );
  }

  String _passwordPage(PageContext c, Map<String, List<String>> errors) {
    String field(
      String name,
      String label,
      Map<String, Object> widget, {
      bool helpText = true,
    }) {
      final fieldErrors = errors[name] ?? const <String>[];
      final attrs = fieldAttributes(
        name,
        widget: widget,
        required: true,
        djangoHelpText: helpText,
        errors: fieldErrors,
        extra: const {'class': 'form-input'},
      );
      return '''
      <div class="form-group">
        ${fieldLabel(name, label)}
        ${inputField('password', name, null, attrs)}
        ${errorList(name, fieldErrors)}
      </div>''';
    }

    return layout(
      c,
      title: 'Change password - Linkding',
      content:
          '''
  <main class="auth-page" aria-labelledby="main-heading">
    <div class="section-header">
      <h1 id="main-heading">Change Password</h1>
    </div>
    <form method="post" action="/change-password/">
      ${c.csrfInput}
${field('old_password', 'Old password', const {'autocomplete': 'current-password', 'autofocus': true}, helpText: false)}
${field('new_password1', 'New password', const {'autocomplete': 'new-password'})}
${field('new_password2', 'Confirm new password', const {'autocomplete': 'new-password'})}
      <input type="submit"
             value="Change Password"
             class="btn btn-primary width-100 mt-4">
    </form>
  </main>''',
    );
  }

  /// Where to go after signing in: [next] when it stays on this site.
  static String _safeNext(String next) {
    if (next.isEmpty || !next.startsWith('/') || next.startsWith('//')) {
      return '/bookmarks';
    }
    return next;
  }

  String _page(
    PageContext c, {
    required String next,
    String username = '',
    bool failed = false,
  }) {
    final error = failed
        ? '\n        <p class="form-input-hint is-error">Your username and password '
              "didn't match. Please try again.</p>"
        : '';
    final value = username.isEmpty ? '' : ' value="${e(username)}"';
    return layout(
      c,
      title: 'Login - Linkding',
      content:
          '''
  <main class="auth-page" aria-labelledby="main-heading">
    <div class="section-header">
      <h1 id="main-heading">Login</h1>
    </div>
      <form method="post" action="/login/">
        ${c.csrfInput}$error
        <div class="form-group">
          <label for="id_username" class="form-label">Username</label>
          <input type="text" name="username"$value autofocus autocapitalize="none" autocomplete="username" maxlength="150" aria-invalid="false" class="form-input" required id="id_username">
        </div>
        <div class="form-group">
          <label for="id_password" class="form-label">Password</label>
          <input type="password" name="password" autocomplete="current-password" aria-invalid="false" class="form-input" required id="id_password">
        </div>
        <input type="submit" value="Login" class="btn btn-primary width-100 mt-4" />
        <input type="hidden" name="next" value="${e(next)}" />
      </form>
  </main>''',
    );
  }
}
