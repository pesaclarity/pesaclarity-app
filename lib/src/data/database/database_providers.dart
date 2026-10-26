import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// The single open database. Override in tests with an in-memory database.
///
/// It opens on first use, which the router holds back until app lock has
/// released the key.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = openEncryptedDatabase(ref.watch(databaseKeyStoreProvider));
  ref.onDispose(db.close);
  return db;
});
