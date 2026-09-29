import 'package:dust_dart/db.dart';

part 'user_rows.g.dart';

/// `auth_user`, password hash included.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class UserRow {
  const UserRow({
    required this.id,
    required this.password,
    required this.isSuperuser,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.isStaff,
    required this.isActive,
    required this.dateJoined,
    this.lastLogin,
  });

  final int id;

  /// Django's `algorithm$iterations$salt$hash`.
  final String password;

  final DateTime? lastLogin;
  final bool isSuperuser;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final bool isStaff;
  final bool isActive;
  final DateTime dateJoined;
}

/// A user's id and name, for the shared bookmarks filter.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class UserNameRow {
  const UserNameRow({required this.id, required this.username});

  final int id;
  final String username;
}

/// `bookmarks_apitoken`.
@Derive([FromRow()])
@Sqlx(renameAll: SqlxRename.snakeCase)
final class ApiTokenRow {
  const ApiTokenRow({
    required this.id,
    required this.key,
    required this.name,
    required this.created,
    required this.userId,
  });

  final int id;
  final String key;
  final String name;
  final DateTime created;
  final int userId;
}
