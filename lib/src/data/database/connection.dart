import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../domain/spaces/space.dart';
import 'app_database.dart';
import 'database_key_store.dart';

const _fileName = 'pesaclarity.sqlite';
const _activeSpaceFileName = 'active-space';

/// The database file for [spaceId] on this phone. Personal keeps the
/// original file name.
Future<File> databaseFile([String spaceId = personalSpaceId]) async {
  final dir = await getApplicationSupportDirectory();
  final name = spaceId == personalSpaceId
      ? _fileName
      : 'pesaclarity-space-$spaceId.sqlite';
  return File(p.join(dir.path, name));
}

/// The space open when the app last closed. Only its id is kept here, so it
/// can be read before the database key is released.
Future<String> readActiveSpaceId() async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, _activeSpaceFileName));
    if (!await file.exists()) return personalSpaceId;
    final id = (await file.readAsString()).trim();
    return RegExp(r'^[a-z0-9]{1,32}$').hasMatch(id) ? id : personalSpaceId;
  } on Exception {
    return personalSpaceId;
  }
}

Future<void> writeActiveSpaceId(String spaceId) async {
  final dir = await getApplicationSupportDirectory();
  await File(p.join(dir.path, _activeSpaceFileName)).writeAsString(spaceId);
}

/// Opens the SQLCipher-encrypted database in a background isolate.
///
/// [beforeOpen] runs before the file is first touched; a restore uses it to
/// hold new connections while it swaps the file.
AppDatabase openEncryptedDatabase(
  DatabaseKeyStore keyStore, {
  Future<void> Function()? beforeOpen,
  String spaceId = personalSpaceId,
}) {
  return AppDatabase(
    LazyDatabase(() async {
      await beforeOpen?.call();
      final file = await databaseFile(spaceId);
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
