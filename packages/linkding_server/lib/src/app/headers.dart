import 'package:dust_server/server.dart';

/// Django's `SecurityMiddleware` and `XFrameOptionsMiddleware`, as linkding
/// configures them, on every response.
const securityHeaders = SecurityHeaders(referrerPolicy: 'same-origin');

/// `Cross-Origin-Opener-Policy: same-origin`, Django's default, which
/// [SecurityHeaders] leaves out.
final class OpenerPolicy implements Layer {
  const OpenerPolicy();

  @override
  Middleware toMiddleware() =>
      (inner) => (request) async {
        final response = await inner(request);
        return response.change(
          headers: {'cross-origin-opener-policy': 'same-origin'},
        );
      };
}
