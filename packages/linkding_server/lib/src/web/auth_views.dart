import 'package:dust_server/server.dart';

import '../auth/passwords.dart';
import '../auth/sessions.dart';
import '../db/users_repo.dart';
import '../services/errors.dart';
import 'context.dart';
import 'forms.dart';
import 'html.dart';
import 'layout.dart';

/// Signing in and out, and the root redirect; Django's `LoginView`,
/// `LogoutView` and linkding's `root` view.
final class AuthViews {
  AuthViews(this.web);

  final Web web;

  /// `/`: to the bookmarks, or for visitors to the shared bookmarks when
  /// that is the landing page. The query string is kept.
  Future<Response> root(Request request) async {
    final c = await web.context(request);
    final query = request.requestedUri.hasQuery
        ? '?${request.requestedUri.query}'
        : '';
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
