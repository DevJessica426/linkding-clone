import 'package:dust_server/server.dart';

import 'error_pages.dart';
import '../support/html.dart' show q;

/// Turns a page route's failures, which Dust's extractors and handlers
/// report as JSON rejections, into what linkding answers a browser with: a
/// 401 is the redirect to the sign-in page, a 403, 404 or 400 is Django's
/// page for it, and anything unexpected is its 500 page.
final class PageErrors implements Layer {
  const PageErrors(this.pages);

  final ErrorPages pages;

  @override
  Middleware toMiddleware() =>
      (inner) => (request) async {
        final response = await inner(request);
        final type = response.headers['content-type'] ?? '';
        if (response.statusCode < 400 || !type.startsWith('application/json')) {
          return response;
        }
        return switch (response.statusCode) {
          401 => _signIn(request),
          403 => pages.forbidden(),
          404 => pages.notFound(),
          405 => Response(405, headers: {'allow': ?response.headers['allow']}),
          < 500 => pages.badRequest(),
          _ => pages.serverError(),
        };
      };

  /// Django's `redirect_to_login` to linkding's `LOGIN_URL`, `/login`,
  /// which then gains its slash.
  static Response _signIn(Request request) {
    final uri = request.requestedUri;
    final path = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    return Redirect.found('/login?next=${q(path)}').intoResponse();
  }
}
