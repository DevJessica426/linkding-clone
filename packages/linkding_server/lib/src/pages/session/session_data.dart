import 'package:dust_server/server.dart';

import '../../accounts/sessions.dart' show sessionCookie;
import '../../db/database.dart';
import '../../db/rows/rows.dart';
import '../../db/repos/settings_repo.dart';
import '../../db/or_throw.dart';
import 'visitor.dart';

/// What Django keeps in a signed-in visitor's session between requests:
/// one-time messages ("Tag created") and single values such as a new API
/// token's key. Visitors who are not signed in have no session to keep
/// them in.
final class SessionData {
  const SessionData._(this._key, this._repo);

  final String? _key;
  final SettingsRepo _repo;

  /// The session of the visitor behind [request].
  static Future<SessionData> of(Request request) async {
    final visitor = await request.extract(const Extension<Visitor>());
    final db = (await request.state<LinkdingDatabase>()).connection;
    final key = CookieJar.of(request).values[sessionCookie];
    return SessionData._(
      visitor.isAuthenticated ? key : null,
      SettingsRepo(db),
    );
  }

  /// Django's `messages.success` and friends.
  Future<void> addMessage(
    String message, {
    String level = 'success',
    String extraTags = '',
  }) async {
    final key = _key;
    if (key == null) return;
    (await _repo.addMessage(key, level, message, extraTags)).orThrow;
  }

  /// The waiting messages, which are shown once.
  Future<List<MessageRow>> takeMessages() async {
    final key = _key;
    if (key == null) return const [];
    return (await _repo.takeMessages(key)).orThrow;
  }

  /// Keeps [value] for a later request.
  Future<void> set(String name, String value) async {
    final key = _key;
    if (key == null) return;
    (await _repo.setSessionValue(key, name, value)).orThrow;
  }

  /// A kept value, removed as it is read: `request.session.pop`.
  Future<String?> pop(String name) async {
    final key = _key;
    if (key == null) return null;
    return (await _repo.popSessionValue(key, name)).orThrow;
  }
}

/// What `messages.html` reads.
Map<String, Object?> messageValues(List<MessageRow> messages) => {
  'hasMessages': messages.isNotEmpty,
  'messages': [
    for (final m in messages) {'tags': m.tags, 'message': m.message},
  ],
};
