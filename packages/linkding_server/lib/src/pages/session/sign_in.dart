import 'package:dust_server/server.dart';

import '../../db/rows/rows.dart';
import 'visitor.dart';

/// linkding's `@login_required`: the signed-in user, or a 401 that
/// [PageErrors] answers with the sign-in page. Installed on a router with
/// `routeLayer(fromExtractor(const RequireSignIn()))`.
final class RequireSignIn implements FromRequestParts<UserRow> {
  const RequireSignIn();

  @override
  Future<Result<UserRow, Rejection>> extract(Request request) async {
    switch (await const Extension<Visitor>().extract(request)) {
      case Err(:final error):
        return Err(error);
      case Ok(value: Visitor(:final user)):
        return user == null
            ? const Err(Rejection.unauthorized('sign in first'))
            : Ok(user);
    }
  }
}
