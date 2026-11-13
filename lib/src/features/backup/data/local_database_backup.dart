import 'dart:io';
import 'dart:isolate';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/connection.dart';
import '../../../data/database/database_key_store.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/spaces/space.dart';
import '../../spaces/application/spaces_providers.dart';

/// A consistent copy of the database, encrypted with its own random key.
final class DatabaseSnapshot {
  const DatabaseSnapshot({
    required this.file,
    required this.keyHex,
    required this.schemaVersion,
  });

  final File file;
  final String keyHex;
  final int schemaVersion;
}

/// Why a decrypted backup cannot replace the data on this phone.
final class RestoredDataException implements Exception {
  const RestoredDataException(this.message);

  final String message;

  @override
  String toString() => 'RestoredDataException: $message';
}

/// The app's data as backups see it: snapshot it, or replace it.
abstract interface class LocalDataStore {
  /// The open space, which a share copy and a restore are for.
  String get openSpace;

  /// Every space on this phone, Personal first; each is backed up.
  Future<List<String>> spaces();

  /// Writes a snapshot of [space]'s data (the open space when null) into
  /// [directory].
  Future<DatabaseSnapshot> snapshot(Directory directory, {String? space});

  /// Checks [staged] (keyed with [stagedKeyHex]) and, only if it is sound,
  /// makes it the app's data. The current data stays in place if any step
  /// fails.
  Future<void> replaceWith(File staged, String stagedKeyHex);
}

/// Copies [db] into [file] with `sqlcipher_export`, under a fresh random key.
///
/// The copy is taken in one statement, so it is consistent even while the
/// app keeps writing. Ask's conversations and shortcuts are left out.
Future<String> exportDatabase(AppDatabase db, File file) async {
  final key = generateDatabaseKey();
  if (file.existsSync()) await file.delete();
  await db.customStatement('ATTACH DATABASE ? AS backup_snapshot KEY ?', [
    file.path,
    "x'$key'",
  ]);
  try {
    await db.customSelect("SELECT sqlcipher_export('backup_snapshot')").get();
    // Ask conversations stay on this phone: the copy keeps the tables, empty.
    for (final table in db.askTables) {
      await db.customStatement(
        'DELETE FROM backup_snapshot.${table.actualTableName}',
      );
    }
    await db.customStatement(
      'PRAGMA backup_snapshot.user_version = ${db.schemaVersion}',
    );
  } finally {
    await db.customStatement('DETACH DATABASE backup_snapshot');
  }
  return key;
}

/// Opens [path] with [stagedKeyHex], checks it is a sound Pesa Clarity
/// database no newer than [maxSchemaVersion], then re-keys it to [deviceKeyHex].
///
/// Synchronous so it can run in a background isolate.
void checkAndRekeyDatabase({
  required String path,
  required String stagedKeyHex,
  required String deviceKeyHex,
  required int maxSchemaVersion,
}) {
  final db = sqlite3.open(path);
  try {
    applyCipherKey(db, stagedKeyHex);
    final List<Object?> integrity;
    try {
      integrity = [
        for (final row in db.select('PRAGMA integrity_check')) row.values.first,
      ];
    } on SqliteException {
      throw const RestoredDataException('The backup data is unreadable.');
    }
    if (integrity.length != 1 || integrity.single != 'ok') {
      throw const RestoredDataException('The backup data is damaged.');
    }
    final version = db.select('PRAGMA user_version').first.values.first! as int;
    if (version < 1) {
      throw const RestoredDataException(
        'This file does not hold Pesa Clarity data.',
      );
    }
    if (version > maxSchemaVersion) {
      throw const RestoredDataException(
        'This backup comes from a newer Pesa Clarity. Update the app, then '
        'restore it.',
      );
    }
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'transactions'",
    );
    if (tables.isEmpty) {
      throw const RestoredDataException(
        'This file does not hold Pesa Clarity data.',
      );
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(deviceKeyHex)) {
      throw ArgumentError('Device key must be 64 lowercase hex characters');
    }
    db.execute("PRAGMA rekey = \"x'$deviceKeyHex'\"");
  } finally {
    db.close();
  }
}

/// Moves [staged] into [live]'s place, putting the old file back if the move
/// fails. The old file is removed only after the new one is in place.
Future<void> swapDatabaseFiles({
  required File live,
  required File staged,
}) async {
  const sidecars = ['-journal', '-wal', '-shm'];
  final aside = '${live.path}.before-restore';
  final moved = <String, String>{};
  try {
    for (final suffix in ['', ...sidecars]) {
      final file = File('${live.path}$suffix');
      if (file.existsSync()) {
        final target = '$aside$suffix';
        if (File(target).existsSync()) await File(target).delete();
        await file.rename(target);
        moved[file.path] = target;
      }
    }
    await staged.rename(live.path);
  } on Object {
    for (final MapEntry(key: original, value: target) in moved.entries) {
      if (File(original).existsSync()) await File(original).delete();
      await File(target).rename(original);
    }
    rethrow;
  }
  for (final target in moved.values) {
    await File(target).delete();
  }
}

/// [LocalDataStore] for the SQLCipher database the app runs on.
class SqlCipherLocalDataStore implements LocalDataStore {
  SqlCipherLocalDataStore(this._ref);

  final Ref _ref;

  @override
  String get openSpace => _ref.read(activeSpaceIdProvider);

  @override
  Future<List<String>> spaces() async => [
    for (final s in spacesFromJson(
      await _ref
          .read(mainSettingsRepositoryProvider)
          .readJson(SpacesController.settingsKey),
    ))
      s.id,
  ];

  @override
  Future<DatabaseSnapshot> snapshot(
    Directory directory, {
    String? space,
  }) async {
    final id = space ?? openSpace;
    final AppDatabase db;
    var close = false;
    if (id == openSpace) {
      db = _ref.read(appDatabaseProvider);
    } else if (id == personalSpaceId) {
      db = _ref.read(personalDatabaseProvider);
    } else {
      // A space that is not open: open its file just for the copy.
      db = openEncryptedDatabase(
        _ref.read(databaseKeyStoreProvider),
        beforeOpen: _ref.read(databaseFileLockProvider).waitUntilFree,
        spaceId: id,
      );
      close = true;
    }
    try {
      final file = File(p.join(directory.path, 'snapshot-$id.sqlite'));
      final key = await exportDatabase(db, file);
      return DatabaseSnapshot(
        file: file,
        keyHex: key,
        schemaVersion: db.schemaVersion,
      );
    } finally {
      if (close) await db.close();
    }
  }

  @override
  Future<void> replaceWith(File staged, String stagedKeyHex) async {
    final deviceKey = await _ref
        .read(databaseKeyStoreProvider)
        .readOrCreateKey();
    final current = _ref.read(appDatabaseProvider);
    final maxSchema = current.schemaVersion;
    final path = staged.path;
    await Isolate.run(
      () => checkAndRekeyDatabase(
        path: path,
        stagedKeyHex: stagedKeyHex,
        deviceKeyHex: deviceKey,
        maxSchemaVersion: maxSchema,
      ),
    );

    final lock = _ref.read(databaseFileLockProvider);
    final release = lock.hold();
    try {
      final spaceId = _ref.read(activeSpaceIdProvider);
      _ref.invalidate(
        spaceId == personalSpaceId
            ? personalDatabaseProvider
            : appDatabaseProvider,
      );
      await lock.close(current);
      await swapDatabaseFiles(
        live: await databaseFile(spaceId),
        staged: staged,
      );
    } finally {
      release();
    }
  }
}
