import 'package:dust_server/server.dart';

import '../auth/passwords.dart';
import '../auth/sessions.dart';
import '../compat/form_data.dart';
import '../db/database.dart';
import '../db/users_repo.dart';
import '../pages/csrf.dart';
import '../pages/render.dart';
import '../pages/visitor.dart';
import '../services/errors.dart';

/// `/login/`: the sign-in form, and signing in. A signed-in visitor goes
/// straight on.
Future<Response> login(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final engine = await request.state<TemplateEngine>();
  if (request.method == 'POST') return _signIn(request, visitor, engine);
  final next = visitor.query['next'] ?? '';
  if (visitor.isAuthenticated) {
    return Redirect.found(_safeNext(next)).intoResponse();
  }
  return _page(engine, visitor, next: next);
}

Future<Response> _signIn(
  Request request,
  Visitor visitor,
  TemplateEngine engine,
) async {
  final form = await request.extract(const PostedForm());
  final username = form['username'] ?? '';
  final password = form['password'] ?? '';
  final next = form['next'] ?? '';
  final db = (await request.state<LinkdingDatabase>()).connection;
  final hasher = await request.state<PasswordHasher>();
  final users = UsersRepo(db);
  final user = (await users.byUsername(username)).orThrow;
  final valid =
      user != null &&
      user.isActive &&
      await hasher.verify(password, user.password);
  if (!valid) {
    // 401 on a failed sign-in, as linkding answers for fail2ban.
    return _page(engine, visitor, next: next, username: username, status: 401);
  }
  if (hasher.mustUpdate(user.password)) {
    (await users.setPassword(user.id, await hasher.hash(password))).orThrow;
  }
  (await users.setLastLogin(user.id, DateTime.now().toUtc())).orThrow;
  final session = await (await request.state<Sessions>()).start(user.id);
  // Django's `login` gives the visitor a new CSRF secret.
  final csrf = CsrfSecret.rotated().setCookie!;
  return Redirect.found(_safeNext(next)).intoResponse().change(
    headers: {
      'set-cookie': [session, csrf],
    },
  );
}

/// `POST /logout/`, then to the sign-in page.
Future<Response> logout(Request request) async {
  if (request.method != 'POST') {
    return Response(405, headers: {'allow': 'POST, OPTIONS'});
  }
  final cleared = await (await request.state<Sessions>()).end(request);
  return Redirect.found('/login')
      .intoResponse()
      .change(headers: {'set-cookie': cleared});
}

/// Where to go after signing in: [next] when it stays on this site.
String _safeNext(String next) {
  if (next.isEmpty || !next.startsWith('/') || next.startsWith('//')) {
    return '/bookmarks';
  }
  return next;
}

Response _page(
  TemplateEngine engine,
  Visitor visitor, {
  required String next,
  String username = '',
  int status = 200,
}) => renderPage(
  engine,
  visitor,
  title: 'Login - Linkding',
  template: 'accounts/login',
  values: {
    'failed': status == 401,
    'hasUsername': username.isNotEmpty,
    'username': username,
    'next': next,
  },
  status: status,
);
