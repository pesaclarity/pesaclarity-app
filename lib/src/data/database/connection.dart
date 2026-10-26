import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'app_database.dart';
import 'database_key_store.dart';

const _fileName = 'pesaclarity.sqlite';

/// The database file on this phone.
Future<File> databaseFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, _fileName));
}

/// Opens the SQLCipher-encrypted database in a background isolate.
///
/// [beforeOpen] runs before the file is first touched; a restore uses it to
/// hold new connections while it swaps the file.
AppDatabase openEncryptedDatabase(
  DatabaseKeyStore keyStore, {
  Future<void> Function()? beforeOpen,
}) {
  return AppDatabase(
    LazyDatabase(() async {
      await beforeOpen?.call();
      final file = await databaseFile();
      final key = await keyStore.readOrCreateKey();
      return NativeDatabase.createInBackground(
        file,
        setup: (db) => applyCipherKey(db, key),
      );
    }),
  );
}

/// Applies a raw 256-bit [hexKey] to [db], refusing to continue without SQLCipher.
///
/// Must run before any other statement on the connection.
void applyCipherKey(Database db, String hexKey) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hexKey)) {
    throw ArgumentError('Database key must be 64 lowercase hex characters');
  }
  // Fail closed: a plain SQLite build would silently ignore PRAGMA key.
  final version = db.select('PRAGMA cipher_version');
  if (version.isEmpty) {
    throw StateError('SQLCipher is not available; refusing to open database');
  }
  // The x'' form passes the raw key and skips SQLCipher's passphrase KDF.
  db.execute("PRAGMA key = \"x'$hexKey'\"");
}
