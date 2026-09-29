import 'package:dust_server/server.dart';

/// The pages Django answers a failure with, from `web/templates/errors/`.
final class ErrorPages {
  const ErrorPages(this.engine);

  final TemplateEngine engine;

  Response notFound() =>
      render(engine, 'errors/not-found', const {}, status: 404);

  Response forbidden() =>
      render(engine, 'errors/forbidden', const {}, status: 403);

  Response badRequest() =>
      render(engine, 'errors/bad-request', const {}, status: 400);

  Response serverError() =>
      render(engine, 'errors/server-error', const {}, status: 500);

  /// The CSRF failure page, with Django's [reason].
  Response csrfFailure(String reason) =>
      render(engine, 'errors/csrf', {'reason': reason}, status: 403);
}
