// A backup file goes back only into the space it is a copy of: a file of
// another space is refused, with a plain note, and nothing changes. The
// app's own providers on real encrypted files; made-up data only.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pesaclarity/src/core/backup/backup.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/backup/application/backup_providers.dart';
import 'package:pesaclarity/src/features/backup/data/backup_settings_repository.dart';
import 'package:pesaclarity/src/features/backup/data/key_value_store.dart';
import 'package:pesaclarity/src/features/backup/data/local_database_backup.dart';
import 'package:pesaclarity/src/features/backup/presentation/restore_flow.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';

import '../../helpers/spaces_harness.dart';

const _passphrase = 'made-up passphrase';
final _now = DateTime.utc(2026, 11, 20, 9);

void main() {
  late ProviderContainer c;
  late Directory dir;
  late String shopId;

  /// Records KES [shillings] of cash from [who] in the open space.
  Future<void> record(int shillings, String who) async {
    final cash = await c
        .read(accountsRepositoryProvider)
        .cashAccount(name: 'Cash', openingDate: _now);
    await c
        .read(transactionsRepositoryProvider)
        .add(
          TransactionsCompanion.insert(
            accountId: cash,
            occurredAt: _now,
            amountMinor: shillings * 100,
            direction: TransactionDirection.inflow,
            source: TransactionSource.manual,
            counterpartyName: Value(who),
          ),
        );
  }

  Future<List<String?>> names() async {
    final db = c.read(appDatabaseProvider);
    return [
      for (final t in await db.select(db.transactions).get())
        t.counterpartyName,
    ];
  }

  Future<void> open(String spaceId) =>
      c.read(activeSpaceIdProvider.notifier).switchTo(spaceId);

  Future<File> backupOf(String spaceId) async => c
      .read(backupServiceProvider)
      .createBackupFile(
        await Directory(p.join(dir.path, 'phone')).create(),
        space: spaceId,
      );

  /// What a file made before backups named their space holds: [spaceId]'s
  /// data with no space in the manifest.
  Future<File> olderBackupOf(String spaceId) async {
    final work = await Directory(p.join(dir.path, 'older')).create();
    final snapshot = await c
        .read(localDataStoreProvider)
        .snapshot(work, space: spaceId);
    final out = File(p.join(work.path, 'older-$spaceId.pcbackup'));
    final secrets = await c
        .read(backupSettingsRepositoryProvider)
        .readSecrets();
    await BackupFiles.write(
      snapshot: snapshot.file.path,
      snapshotKeyHex: snapshot.keyHex,
      schemaVersion: snapshot.schemaVersion,
      createdAt: _now,
      output: out.path,
      passphrase: _passphrase,
      recoveryKeyBytes: secrets!.recoveryKey.bytes,
      kdfParams: const KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1),
    );
    return out;
  }

  Future<Object?> restore(File file) async {
    try {
      await c
          .read(backupServiceProvider)
          .restoreFromFile(file, const PassphraseCredential(_passphrase));
      return null;
    } on Object catch (e) {
      return e;
    }
  }

  Future<Map<String, Object?>> personalAsItIs() async => {
    'records': await names(),
    'spaces': [for (final s in await c.read(spacesProvider.future)) s.name],
    'kind': (await c.read(personalDatabaseProvider).spaceKind()).name,
  };

  setUp(() async {
    (c, dir) = await spacesOnFiles(
      clock: () => _now,
      overrides: [
        backupKeyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        backupKdfParamsProvider.overrideWithValue(
          const KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1),
        ),
      ],
    );
    await record(500, 'PERSONAL TEST PAYER');
    shopId = await c
        .read(spacesProvider.notifier)
        .add('Test Shop', SpaceKind.business);
    await record(650, 'SHOP TEST CUSTOMER');
    await c
        .read(backupSettingsRepositoryProvider)
        .writeSecrets(
          BackupSecrets(
            passphrase: _passphrase,
            recoveryKey: RecoveryKey.generate(),
          ),
        );
  });

  test('the shop\'s file restored in Personal is refused, and Personal '
      'stays as it is', () async {
    final file = await backupOf(shopId);
    await open(personalSpaceId);

    final refused = await restore(file);

    expect(refused, isA<RestoredDataException>());
    expect(
      restoreErrorMessage(refused!),
      'This backup is of another space. Open that space, then restore it '
      'there. Your data is unchanged.',
    );
    expect(await personalAsItIs(), {
      'records': ['PERSONAL TEST PAYER'],
      'spaces': ['Personal', 'Test Shop'],
      'kind': 'personal',
    });
  });

  test('Personal\'s file restored in the shop is refused', () async {
    await open(personalSpaceId);
    final file = await backupOf(personalSpaceId);
    await open(shopId);

    expect(await restore(file), isA<RestoredDataException>());
    expect(await names(), ['SHOP TEST CUSTOMER']);
    expect(await c.read(appDatabaseProvider).spaceKind(), SpaceKind.business);
  });

  test('a space\'s own file restores into it', () async {
    final file = await backupOf(shopId);
    await record(300, 'LATER TEST CUSTOMER');
    expect(await names(), hasLength(2));

    expect(await restore(file), isNull);
    expect(await names(), ['SHOP TEST CUSTOMER']);
  });

  group('a file made before backups named their space', () {
    test('of the shop, is refused in Personal', () async {
      final file = await olderBackupOf(shopId);
      await open(personalSpaceId);

      expect(await restore(file), isA<RestoredDataException>());
      expect(await personalAsItIs(), {
        'records': ['PERSONAL TEST PAYER'],
        'spaces': ['Personal', 'Test Shop'],
        'kind': 'personal',
      });
    });

    test('of Personal, restores into Personal', () async {
      await open(personalSpaceId);
      final file = await olderBackupOf(personalSpaceId);
      await record(100, 'LATER TEST PAYER');

      expect(await restore(file), isNull);
      expect(await names(), ['PERSONAL TEST PAYER']);
    });
  });
}
