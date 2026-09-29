import 'package:dust_dart/db.dart';

part 'settings_rows.g.dart';

/// `bookmarks_globalsettings`.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class GlobalSettingsRow {
  const GlobalSettingsRow({
    required this.id,
    required this.landingPage,
    required this.enableLinkPrefetch,
    this.guestProfileUserId,
  });

  final int id;
  final String landingPage;
  final int? guestProfileUserId;
  final bool enableLinkPrefetch;
}

/// `bookmarks_toast`.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class ToastRow {
  const ToastRow({
    required this.id,
    required this.key,
    required this.message,
    required this.acknowledged,
    required this.ownerId,
  });

  final int id;
  final String key;
  final String message;
  final bool acknowledged;
  final int ownerId;
}

/// A one-time message waiting to be shown.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class MessageRow {
  const MessageRow({
    required this.level,
    required this.message,
    required this.extraTags,
  });

  /// `success`, `error`, ...
  final String level;
  final String message;
  final String extraTags;

  /// Django's `message.tags`: the extra tags, then the level.
  String get tags => [extraTags, level].where((t) => t.isNotEmpty).join(' ');
}
