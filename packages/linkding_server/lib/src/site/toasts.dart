import 'package:dust_server/server.dart';

import '../compat/django.dart';
import '../compat/form_data.dart';
import '../db/database.dart';
import '../db/settings_repo.dart';
import '../pages/return_url.dart';
import '../pages/visitor.dart';
import '../services/errors.dart';

/// `/toasts/acknowledge`: dismisses one of the user's toasts, then back to
/// the page it was shown on. A missing or non-numeric `toast` is an error
/// in linkding; someone else's toast is not found.
Future<Result<Response, Rejection>> acknowledgeToast(Request request) async {
  final visitor = await request.extract(const Extension<Visitor>());
  final form = await request.extract(const PostedForm());
  final id = pythonInt(form['toast']);
  if (id == null) return const Err(Rejection.internal());
  final db = (await request.state<LinkdingDatabase>()).connection;
  final acknowledged = id < -2147483648 || id > 2147483647
      ? null
      : (await SettingsRepo(db).acknowledge(id, visitor.signedIn.id)).orThrow;
  if (acknowledged == null) {
    return const Err(Rejection.notFound('Toast does not exist'));
  }
  final back = safeReturnUrl(visitor.query['return_url'], '/bookmarks');
  return Ok(Redirect.found(back).intoResponse());
}
