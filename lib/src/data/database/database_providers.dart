import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'connection.dart';
import 'database_key_store.dart';

final databaseKeyStoreProvider = Provider<DatabaseKeyStore>(
  (ref) => SecureStorageDatabaseKeyStore(),
);

/// The single open database. Override in tests with an in-memory database.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = openEncryptedDatabase(ref.watch(databaseKeyStoreProvider));
  ref.onDispose(db.close);
  return db;
});
