import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'connection.dart';
import 'database_key_store.dart';

final databaseKeyStoreProvider = Provider<DatabaseKeyStore>(
  (ref) => SecureStorageDatabaseKeyStore(),
);

/// Coordinates replacing the database file while the app is running.
final databaseFileLockProvider = Provider<DatabaseFileLock>(
  (ref) => DatabaseFileLock(),
);

/// The single open database. Override in tests with an in-memory database.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final lock = ref.watch(databaseFileLockProvider);
  final db = openEncryptedDatabase(
    ref.watch(databaseKeyStoreProvider),
    beforeOpen: lock.waitUntilFree,
  );
  ref.onDispose(() => unawaited(lock.close(db)));
  return db;
});

/// Holds new database connections while the file is being swapped, and
/// closes each connection exactly once.
class DatabaseFileLock {
  final _closing = Expando<Future<void>>();
  Completer<void>? _held;

  /// Completes once no swap is in progress.
  Future<void> waitUntilFree() async {
    while (_held != null) {
      await _held!.future;
    }
  }

  /// Closes [db], or returns the close already under way.
  Future<void> close(AppDatabase db) => _closing[db] ??= db.close();

  /// Holds new connections until the returned callback is called.
  void Function() hold() {
    if (_held != null) throw StateError('The database is already held.');
    final held = _held = Completer<void>();
    return () {
      _held = null;
      held.complete();
    };
  }
}
