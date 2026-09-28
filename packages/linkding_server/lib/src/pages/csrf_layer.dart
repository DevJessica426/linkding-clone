import 'package:dust_server/server.dart';

import '../compat/form_data.dart';
import 'csrf.dart';
import 'error_pages.dart';

/// Django's CSRF middleware for the pages: a request with an unsafe method
/// has to carry the visitor's token, in the form or in `X-CSRFToken`, or it
/// is answered with the CSRF failure page before any handler runs.
///
/// The body is read here to find the token, and handed on unread.
final class CsrfProtection implements Layer {
  const CsrfProtection(this.pages);

  final ErrorPages pages;

  static const _safe = {'GET', 'HEAD', 'OPTIONS', 'TRACE'};

  @override
  Middleware toMiddleware() =>
      (inner) => (request) async {
        if (_safe.contains(request.method)) return inner(request);
        final body = await request.read().expand((chunk) => chunk).toList();
        String? submitted;
        if (request.method == 'POST') {
          final form = await readFormData(request.change(body: body));
          final token = form['csrfmiddlewaretoken'] ?? '';
          // An empty field falls back to the header, as in Django.
          submitted = token.isEmpty ? null : token;
        }
        final failure = csrfFailure(request, submitted);
        if (failure != null) return pages.csrfFailure(failure);
        return inner(request.change(body: body));
      };
}
