import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/connection.dart';
import 'package:pesaclarity/src/data/database/database_key_store.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_role.dart';
import 'package:pesaclarity/src/domain/ledger/own_transfers.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  group('SQLCipher', () {
    test('the bundled SQLite build is SQLCipher', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      expect(db.select('PRAGMA cipher_version'), isNotEmpty);
    });

    test('applyCipherKey accepts a generated key', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      applyCipherKey(db, generateDatabaseKey());
      db.execute('CREATE TABLE t (x INTEGER)');
    });

    test('applyCipherKey rejects malformed keys', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      expect(() => applyCipherKey(db, "abc'; DROP"), throwsArgumentError);
    });

    test('generated keys are 256-bit hex and differ', () {
      final a = generateDatabaseKey();
      expect(a, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(generateDatabaseKey(), isNot(a));
    });
  });

  group('repositories', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('stores money as integer minor units and finds by receipt', () async {
      final accounts = DriftAccountsRepository(db);
      final transactions = DriftTransactionsRepository(db);

      final accountId = await accounts.add(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: DateTime.utc(2026, 10),
        ),
      );
      await transactions.add(
        TransactionsCompanion.insert(
          accountId: accountId,
          occurredAt: DateTime.utc(2026, 10, 3, 9, 30),
          amountMinor: 120050,
          direction: TransactionDirection.outflow,
          source: TransactionSource.sms,
          receiptNo: const Value('TEST000001'),
        ),
      );

      final found = await transactions.findByReceipt(accountId, 'TEST000001');
      expect(found, isNotNull);
      expect(found!.amountMinor, 120050);
      expect(found.currency, 'KES');
      expect(await transactions.findByReceipt(accountId, 'MISSING'), isNull);

      final recent = await transactions.watchRecent().first;
      expect(recent, hasLength(1));
      expect((await accounts.watchAll().first).single.name, 'M-Pesa');
    });

    test('enforces foreign keys', () async {
      await expectLater(
        DriftTransactionsRepository(db).add(
          TransactionsCompanion.insert(
            accountId: 999,
            occurredAt: DateTime.utc(2026, 10),
            amountMinor: 100,
            direction: TransactionDirection.inflow,
            source: TransactionSource.manual,
          ),
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'reads ledger entries with resolved categories and stores pairs',
      () async {
        final accounts = DriftAccountsRepository(db);
        final transactions = DriftTransactionsRepository(db);
        final bank = await accounts.add(
          AccountsCompanion.insert(
            name: 'Bank',
            type: AccountType.bank,
            openingDate: DateTime.utc(2026, 10),
          ),
        );
        final mpesa = await accounts.add(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: DateTime.utc(2026, 10),
          ),
        );
        final food = await db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                name: 'Food',
                type: CategoryType.expense,
                isDailySpending: const Value(true),
              ),
            );
        final shop = await db
            .into(db.payees)
            .insert(
              PayeesCompanion.insert(
                displayName: 'Test Grocer',
                defaultCategoryId: Value(food),
              ),
            );

        Future<int> add(
          int account,
          DateTime at,
          int amount,
          TransactionDirection direction,
          TransactionKind kind, {
          int? payeeId,
        }) => transactions.add(
          TransactionsCompanion.insert(
            accountId: account,
            occurredAt: at,
            amountMinor: amount,
            direction: direction,
            kind: Value(kind),
            payeeId: Value(payeeId),
            source: TransactionSource.sms,
          ),
        );

        final out = await add(
          bank,
          DateTime.utc(2026, 10, 5, 6),
          500000,
          TransactionDirection.outflow,
          TransactionKind.bank,
        );
        final into = await add(
          mpesa,
          DateTime.utc(2026, 10, 5, 6, 3),
          500000,
          TransactionDirection.inflow,
          TransactionKind.received,
        );
        final groceries = await add(
          mpesa,
          DateTime.utc(2026, 10, 5, 9),
          84000,
          TransactionDirection.outflow,
          TransactionKind.till,
          payeeId: shop,
        );
        await add(
          mpesa,
          DateTime.utc(2026, 11, 2),
          100,
          TransactionDirection.outflow,
          TransactionKind.airtime,
        );

        final from = DateTime.utc(2026, 9, 30, 21);
        final to = DateTime.utc(2026, 10, 31, 21);
        final entries = await transactions.ledgerEntries(from: from, to: to);
        expect(entries.map((e) => e.id), [out, into, groceries]);
        final grocery = entries.last;
        expect(grocery.categoryId, food);
        expect(grocery.categoryType, CategoryType.expense);
        expect(grocery.isDailySpending, isTrue);
        expect(roleOf(entries[1]), LedgerRole.awaitingPayee);

        await transactions.saveTransferPairs(findOwnTransfers(entries));
        final linked = await transactions.ledgerEntries(from: from, to: to);
        expect(linked[0].transferPairId, into);
        expect(linked[1].transferPairId, out);
        expect(roleOf(linked[1]), LedgerRole.ownTransfer);
      },
    );
  });

  test('migrates a version 1 database by adding kind and fee', () async {
    final dir = await Directory.systemTemp.createTemp('pesaclarity_migration');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/v1.sqlite');

    final v2 = AppDatabase(NativeDatabase(file));
    await v2.customSelect('SELECT 1').get();
    await v2.customStatement('ALTER TABLE transactions DROP COLUMN kind');
    await v2.customStatement('ALTER TABLE transactions DROP COLUMN fee_minor');
    await v2.customStatement('PRAGMA user_version = 1');
    await v2.close();

    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final columns = await db
        .customSelect('PRAGMA table_info(transactions)')
        .map((row) => row.read<String>('name'))
        .get();
    expect(columns, containsAll(['kind', 'fee_minor']));
  });
}
