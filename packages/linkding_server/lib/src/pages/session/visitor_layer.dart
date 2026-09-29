import 'package:dust_dart/db.dart';
import 'package:dust_server/server.dart';

import '../../accounts/sessions.dart';
import '../../core/profile.dart';
import '../../db/or_throw.dart';
import '../../db/repos/profiles_repo.dart';
import '../../db/repos/settings_repo.dart';
import 'csrf.dart';
import 'visitor.dart';

/// Builds the [Visitor] of every page request, once, for the handlers to
/// read with `Extension<Visitor>`, and adds to the page's response what
/// Django's middleware adds: the CSRF cookie when the page used a new
/// secret, `Vary: Cookie`, and an HTML content type on redirects.
final class VisitorLayer implements Layer {
  const VisitorLayer(this.sessions, this.db);

  final Sessions sessions;
  final Executor db;

  @override
  Middleware toMiddleware() =>
      (inner) => (request) async {
        final visitor = await _visit(request);
        final response = await inner(
          request.change(context: {extensionKeyFor<Visitor>(): visitor}),
        );
        return _finish(response, visitor);
      };

  Future<Visitor> _visit(Request request) async {
    final user = await sessions.user(request);
    final global = (await SettingsRepo(db).global()).orThrow!;
    // Visitors see the pages with the guest profile's preferences when one
    // is configured, otherwise with the defaults and favicons on.
    final profileOf = user?.id ?? global.guestProfileUserId;
    final row = profileOf == null
        ? null
        : (await ProfilesRepo(db).profile(profileOf)).orThrow;
    final toasts = user == null
        ? const <Never>[]
        : (await SettingsRepo(db).toasts(user.id)).orThrow;
    return Visitor(
      request: request,
      user: user,
      profile: Profile(row ?? standardProfile),
      settings: global,
      toasts: toasts,
      csrf: CsrfSecret.of(request),
    );
  }

  static Response _finish(Response response, Visitor visitor) {
    final redirect = response.statusCode >= 300 && response.statusCode < 400;
    final cookie = visitor.csrf.used ? visitor.csrf.setCookie : null;
    return response.change(
      headers: {
        'vary': 'Cookie',
        if (redirect && !response.headers.containsKey('content-type'))
          'content-type': 'text/html; charset=utf-8',
        if (cookie != null)
          'set-cookie': [...?response.headersAll['set-cookie'], cookie],
      },
    );
  }
}
