import 'package:dust_dart/db.dart';

extension ResultOrThrow<T> on Result<T, SqlxError> {
  /// The value, or the database error thrown.
  ///
  /// A database failure is nothing a request can recover from; thrown, it
  /// reaches the router's error handler and becomes a 500 with the real error
  /// logged rather than sent to the client, which is what Django does too.
  T get orThrow => unwrapOrElse((error) => throw error);
}
