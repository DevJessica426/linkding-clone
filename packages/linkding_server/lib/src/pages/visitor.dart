import 'package:dust_server/server.dart';

import '../core/profile.dart';
import '../db/rows.dart';
import 'csrf.dart';

/// Who is asking for a page: the signed-in user (null for a visitor), the
/// preferences the pages follow (the guest profile's for visitors), the
/// global settings, the user's toasts, and the request's CSRF secret.
///
/// [VisitorLayer] builds one per page request; a handler reads it with
/// `request.extract(const Extension<Visitor>())`.
final class Visitor {
  Visitor({
    required this.request,
    required this.user,
    required this.profile,
    required this.settings,
    required this.toasts,
    required this.csrf,
  });

  final Request request;
  final UserRow? user;
  final Profile profile;
  final GlobalSettingsRow settings;
  final List<ToastRow> toasts;
  final CsrfSecret csrf;

  bool get isAuthenticated => user != null;

  /// The signed-in user, for a handler behind [RequireSignIn].
  UserRow get signedIn => user!;

  /// This request with [profile] in place of the saved preferences.
  Visitor withProfile(Profile profile) => Visitor(
    request: request,
    user: user,
    profile: profile,
    settings: settings,
    toasts: toasts,
    csrf: csrf,
  );

  /// The masked token a form carries: `{% csrf_token %}`'s value.
  late final String csrfToken = csrf.masked();

  /// `request.path`.
  String get path => request.requestedUri.path;

  /// `request.get_full_path()`.
  String get fullPath {
    final uri = request.requestedUri;
    return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  }

  /// The query string's values, the last of a repeated name.
  Map<String, String> get query => request.requestedUri.queryParameters;

  /// The scheme and host the visitor asked for.
  String get baseUrl {
    final uri = request.requestedUri;
    return '${uri.scheme}://${request.headers['host'] ?? uri.authority}';
  }
}
