import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/connection.dart';
import 'package:pesaclarity/src/data/database/database_key_store.dart';
import 'package:pesaclarity/src/features/backup/data/local_database_backup.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('local_db_backup_test');
  });
  tearDown(() => dir.delete(recursive: true));

  Future<(File, String)> exportSample() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.customStatement(
      'INSERT INTO accounts (name, type, currency, opening_date) '
      "VALUES ('John M-Pesa', 'mpesa', 'KES', 0)",
    );
    final file = File(p.join(dir.path, 'snapshot.sqlite'));
    final key = await exportDatabase(db, file);
    return (file, key);
  }

  test('exports an encrypted, re-keyable copy', () async {
    final (file, key) = await exportSample();
    expect(file.existsSync(), isTrue);

    // Unreadable without its key.
    final plain = sqlite3.open(file.path);
    expect(
      () => plain.select('SELECT * FROM sqlite_master'),
      throwsA(anything),
    );
    plain.close();

    final deviceKey = generateDatabaseKey();
    checkAndRekeyDatabase(
      path: file.path,
      stagedKeyHex: key,
      deviceKeyHex: deviceKey,
      maxSchemaVersion: 7,
    );

    final reopened = sqlite3.open(file.path);
    addTearDown(reopened.close);
    applyCipherKey(reopened, deviceKey);
    expect(
      reopened.select('SELECT name FROM accounts').map((r) => r['name']),
      contains('John M-Pesa'),
    );
    expect(reopened.select('PRAGMA user_version').first.values.first, 7);
  });

  test('refuses a backup from a newer schema', () async {
    final (file, key) = await exportSample();
    expect(
      () => checkAndRekeyDatabase(
        path: file.path,
        stagedKeyHex: key,
        deviceKeyHex: generateDatabaseKey(),
        maxSchemaVersion: 6,
      ),
      throwsA(isA<RestoredDataException>()),
    );
  });

  test('refuses a file opened with the wrong key', () async {
    final (file, _) = await exportSample();
    expect(
      () => checkAndRekeyDatabase(
        path: file.path,
        stagedKeyHex: generateDatabaseKey(),
        deviceKeyHex: generateDatabaseKey(),
        maxSchemaVersion: 7,
      ),
      throwsA(isA<RestoredDataException>()),
    );
  });

  group('swapDatabaseFiles', () {
    test('puts the staged file in place and removes the old one', () async {
      final live = File(p.join(dir.path, 'live.sqlite'))
        ..writeAsStringSync('old');
      final staged = File(p.join(dir.path, 'staged.sqlite'))
        ..writeAsStringSync('new');
      await swapDatabaseFiles(live: live, staged: staged);
      expect(live.readAsStringSync(), 'new');
      expect(staged.existsSync(), isFalse);
      expect(dir.listSync(), hasLength(1));
    });

    test('keeps the current file if the swap fails', () async {
      final live = File(p.join(dir.path, 'live.sqlite'))
        ..writeAsStringSync('old');
      final missing = File(p.join(dir.path, 'missing.sqlite'));
      await expectLater(
        swapDatabaseFiles(live: live, staged: missing),
        throwsA(isA<FileSystemException>()),
      );
      expect(live.readAsStringSync(), 'old');
      expect(dir.listSync(), hasLength(1));
    });
  });
}
