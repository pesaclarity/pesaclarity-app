import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/spaces/space.dart';
import 'app_database.dart';
import 'connection.dart';
import 'database_key_store.dart';

/// Holds the database key once app lock releases it.
class ReleasedDatabaseKey {
  String? _key;

  String? get value => _key;

  void release(String key) => _key = key;
}

final releasedDatabaseKeyProvider = Provider<ReleasedDatabaseKey>(
  (ref) => ReleasedDatabaseKey(),
);

final databaseKeyStoreProvider = Provider<DatabaseKeyStore>((ref) {
  final released = ref.watch(releasedDatabaseKeyProvider);
  return UnlockedDatabaseKeyStore(() => released.value);
});

/// Coordinates replacing the database file while the app is running.
final databaseFileLockProvider = Provider<DatabaseFileLock>(
  (ref) => DatabaseFileLock(),
);

/// The space whose database is open. `main` starts it from the space open
/// when the app last closed.
class ActiveSpaceId extends Notifier<String> {
  ActiveSpaceId([this._initial = personalSpaceId]);

  final String _initial;

  @override
  String build() => _initial;

  /// Opens [spaceId]'s database in place of the current one.
  Future<void> switchTo(String spaceId) async {
    if (spaceId == state) return;
    await ref.read(activeSpaceStoreProvider).write(spaceId);
    state = spaceId;
  }
}

final activeSpaceIdProvider = NotifierProvider<ActiveSpaceId, String>(
  ActiveSpaceId.new,
);

/// Remembers the open space between launches.
class ActiveSpaceStore {
  const ActiveSpaceStore();

  Future<void> write(String spaceId) => writeActiveSpaceId(spaceId);
}

final activeSpaceStoreProvider = Provider<ActiveSpaceStore>(
  (ref) => const ActiveSpaceStore(),
);

/// Personal's database, which also keeps app-wide settings and the list of
/// spaces.
final personalDatabaseProvider = Provider<AppDatabase>((ref) {
  final lock = ref.watch(databaseFileLockProvider);
  final db = openEncryptedDatabase(
    ref.watch(databaseKeyStoreProvider),
    beforeOpen: lock.waitUntilFree,
  );
  ref.onDispose(() => unawaited(lock.close(db)));
  return db;
});

/// The open space's database. Override in tests with an in-memory database.
///
/// It opens on first use, which the router holds back until app lock has
/// released the key.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final spaceId = ref.watch(activeSpaceIdProvider);
  if (spaceId == personalSpaceId) return ref.watch(personalDatabaseProvider);
  final lock = ref.watch(databaseFileLockProvider);
  final db = openEncryptedDatabase(
    ref.watch(databaseKeyStoreProvider),
    beforeOpen: lock.waitUntilFree,
    spaceId: spaceId,
  );
  ref.onDispose(() => unawaited(lock.close(db)));
  return db;
});

/// The database for app-wide settings: Personal's, whichever space is open.
final mainDatabaseProvider = Provider<AppDatabase>(
  (ref) => ref.watch(activeSpaceIdProvider) == personalSpaceId
      ? ref.watch(appDatabaseProvider)
      : ref.watch(personalDatabaseProvider),
);

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
