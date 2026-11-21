// Restoring Personal's records (a kept copy, or a backup file) brings back
// its records only: the list of spaces, Recently deleted and the Business
// or personal rules, kept in Personal's file for every space, stay as they
// are. The app's own providers on real encrypted files; made-up data only.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pesaclarity/src/core/backup/backup.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/connection.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/spaces/kept_data.dart';
import 'package:pesaclarity/src/domain/spaces/line_routing.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/backup/application/backup_providers.dart';
import 'package:pesaclarity/src/features/backup/data/backup_settings_repository.dart';
import 'package:pesaclarity/src/features/backup/data/key_value_store.dart';
import 'package:pesaclarity/src/features/spaces/application/routing_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/space_manager.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';

import '../../helpers/spaces_harness.dart';

const _passphrase = 'made-up passphrase';

void main() {
  var now = DateTime.utc(2026, 11, 1, 9);
  late ProviderContainer c;
  late Directory dir;

  Future<void> record(int shillings, String who) async {
    final cash = await c
        .read(accountsRepositoryProvider)
        .cashAccount(name: 'Cash', openingDate: now);
    await c
        .read(transactionsRepositoryProvider)
        .add(
          TransactionsCompanion.insert(
            accountId: cash,
            occurredAt: now,
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

  Future<Map<String, Object?>> everySpace() async {
    c
      ..invalidate(spacesProvider)
      ..invalidate(keptDataProvider)
      ..invalidate(routingRulesProvider);
    return {
      'spaces': [for (final s in await c.read(spacesProvider.future)) s.name],
      'Recently deleted': [
        for (final k in await c.read(keptDataProvider.future))
          '${k.space.name} (${k.kind.name})',
      ],
      'rules': (await c.read(routingRulesProvider.future)).toJson(),
      'locked copies': Directory(p.join(dir.path, 'kept'))
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sqlite'))
          .length,
    };
  }

  /// After Personal's copy is made: a shop sharing M-Pesa, and a rental
  /// added, used and deleted with a kept copy.
  Future<String> laterSpaces() async {
    now = DateTime.utc(2026, 11, 5, 9);
    final shopId = await c
        .read(spacesProvider.notifier)
        .add('Mama Njeri Shop', SpaceKind.business);
    await record(650, 'SHOP TEST CUSTOMER');
    await c
        .read(routingRulesProvider.notifier)
        .setLine(
          'mpesa',
          LineChoice.both,
          businessId: shopId,
          business: c.read(institutionsRepositoryProvider),
          personal: DriftInstitutionsRepository(
            c.read(personalDatabaseProvider),
          ),
        );
    await c
        .read(spacesProvider.notifier)
        .add('Plot 12', SpaceKind.rentalProperty);
    await record(15000, 'PLOT TEST TENANT');
    final plot = (await c.read(spacesProvider.future))
        .singleWhere((s) => s.name == 'Plot 12');
    await c.read(spaceManagerProvider).delete(plot, keep: true);
    return shopId;
  }

  setUp(() async {
    now = DateTime.utc(2026, 11, 1, 9);
    (c, dir) = await spacesOnFiles(
      clock: () => now,
      overrides: [
        backupKeyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        backupKdfParamsProvider.overrideWithValue(
          const KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1),
        ),
      ],
    );
    await record(500, 'PERSONAL TEST PAYER');
  });

  test('Personal\'s cleared records come back; the spaces made since, '
      'Recently deleted and the rules stay', () async {
    await c.read(spaceManagerProvider).clear(Space.personal, keep: true);
    expect(await names(), isEmpty);
    final shopId = await laterSpaces();
    final before = await everySpace();
    expect(before['spaces'], ['Personal', 'Mama Njeri Shop']);

    now = DateTime.utc(2026, 11, 12, 9);
    final cleared = (await c.read(keptDataProvider.future))
        .singleWhere((k) => k.kind == KeptKind.cleared);
    await c.read(spaceManagerProvider).restore(cleared);
    await settle();

    expect(c.read(activeSpaceIdProvider), personalSpaceId);
    expect(await names(), ['PERSONAL TEST PAYER']);
    expect(await everySpace(), {
      'spaces': ['Personal', 'Mama Njeri Shop'],
      'Recently deleted': ['Plot 12 (space)'],
      'rules': {
        'sharedLines': {'mpesa': shopId},
        'people': <String, String>{},
      },
      'locked copies': 1,
    });
    expect((await databaseFile(shopId)).existsSync(), isTrue);
    // The rental's copy can still be opened: it is restored with its key.
    final plot = (await c.read(keptDataProvider.future)).single;
    await c.read(spaceManagerProvider).restore(plot);
    expect(await names(), ['PLOT TEST TENANT']);
  });

  test('a backup file of Personal brings back its records only', () async {
    await c
        .read(backupSettingsRepositoryProvider)
        .writeSecrets(
          BackupSecrets(
            passphrase: _passphrase,
            recoveryKey: RecoveryKey.generate(),
          ),
        );
    final file = await c
        .read(backupServiceProvider)
        .createBackupFile(await Directory(p.join(dir.path, 'phone')).create());
    final shopId = await laterSpaces();
    await c.read(activeSpaceIdProvider.notifier).switchTo(personalSpaceId);
    await record(100, 'LATER TEST PAYER');
    final before = await everySpace();

    await c
        .read(backupServiceProvider)
        .restoreFromFile(file, const PassphraseCredential(_passphrase));
    await settle();

    expect(await names(), ['PERSONAL TEST PAYER']);
    expect(await everySpace(), before);
    expect((await c.read(routingRulesProvider.future)).sharedWith(shopId), {
      'mpesa',
    });
  });
}
