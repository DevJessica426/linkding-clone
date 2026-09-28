/// Signing in and out, and changing the password.
library;

import 'package:dust_server/server.dart';

import '../pages/append_slash.dart';
import '../pages/sign_in.dart';
import 'password_pages.dart';
import 'sign_in_pages.dart';

/// The pages of Django's auth views that linkding uses.
Router accountRoutes() => Router()
  ..route('/login/', any(login))
  ..route('/login', any(appendSlash))
  ..route('/logout/', any(logout))
  ..route('/logout', any(appendSlash))
  ..route('/change-password', any(appendSlash))
  ..route('/password-change-done', any(appendSlash))
  ..merge(
    Router()
      ..routeLayer(fromExtractor(const RequireSignIn()))
      ..route('/change-password/', any(changePassword))
      ..route('/password-change-done/', any(passwordChangeDone)),
  );
