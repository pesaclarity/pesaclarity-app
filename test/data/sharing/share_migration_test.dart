import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';

import '../../domain/fixtures.dart';

Future<int> _version(AppDatabase db) async =>
    (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
      'user_version',
    );

void main() {
  late File file;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('share_migration');
    addTearDown(() => dir.delete(recursive: true));
    file = File('${dir.path}/old.sqlite');
  });

  test(
    'version 48 gives every record a share id, and is safe to run twice',
    () async {
      final old = AppDatabase(NativeDatabase(file));
      final account = await old
          .into(old.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'Cash box',
              type: AccountType.cash,
              openingDate: eat(2026, 1, 1),
            ),
          );
      await old
          .into(old.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: account,
              occurredAt: eat(2026, 11, 2),
              amountMinor: kes(450),
              direction: TransactionDirection.outflow,
              source: TransactionSource.manual,
              counterpartyName: const Value('Mama Mboga'),
            ),
          );
      // As version 47 left it: no ids, no log.
      for (final t in [
        'accounts',
        'categories',
        'transactions',
        'budget_items',
      ]) {
        for (final suffix in ['insert', 'update', 'delete', 'uid_insert']) {
          await old.customStatement('DROP TRIGGER ${t}_share_$suffix');
        }
        await old.customStatement('DROP INDEX ${t}_share_uid');
        await old.customStatement('ALTER TABLE $t DROP COLUMN share_uid');
      }
      for (final table in [
        'share_changes',
        'share_state',
        'share_peers',
        'share_dirty',
        'share_seen',
        'share_files',
      ]) {
        await old.customStatement('DROP TABLE $table');
      }
      for (final c in ['added_by', 'recorded_by']) {
        await old.customStatement('ALTER TABLE transactions DROP COLUMN $c');
      }
      await old.customStatement('PRAGMA user_version = 47');
      await old.close();

      var db = AppDatabase(NativeDatabase(file));
      expect(await _version(db), 48);
      final first = await db.select(db.transactions).getSingle();
      final cash = await db.select(db.accounts).getSingle();
      expect(first.shareUid, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4')));
      expect(cash.shareUid, isNotNull);
      final seeded = await (db.select(
        db.categories,
      )..where((c) => c.key.isNotNull())).get();
      expect(seeded, isNotEmpty);
      for (final c in seeded) {
        expect(c.shareUid, 'key:${c.key}');
      }
      expect(await db.select(db.shareChanges).get(), isEmpty);
      await db.customStatement('PRAGMA user_version = 47');
      await db.close();

      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(await _version(db), 48);
      expect(
        (await db.select(db.transactions).getSingle()).shareUid,
        first.shareUid,
      );
      expect(
        (await db.select(db.accounts).getSingle()).shareUid,
        cash.shareUid,
      );

      // A record added later gets its id too.
      final id = await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: account,
              occurredAt: eat(2026, 11, 3),
              amountMinor: kes(100),
              direction: TransactionDirection.outflow,
              source: TransactionSource.manual,
            ),
          );
      final row = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.shareUid, isNotNull);
      expect(row.shareUid, isNot(first.shareUid));

      // A row copied from another, id and all, gets an id of its own.
      final copy = await db
          .into(db.transactions)
          .insert(first.toCompanion(false).copyWith(id: const Value.absent()));
      final copied = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(copy))).getSingle();
      expect(copied.shareUid, isNot(first.shareUid));
    },
  );
}
