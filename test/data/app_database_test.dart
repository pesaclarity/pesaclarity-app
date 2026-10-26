import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/connection.dart';
import 'package:pesaclarity/src/data/database/database_key_store.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/data/repositories/onboarding_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/categories/default_categories.dart';
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

  group('migrations', () {
    late File file;

    setUp(() async {
      final dir = await Directory.systemTemp.createTemp(
        'pesaclarity_migration',
      );
      addTearDown(() => dir.delete(recursive: true));
      file = File('${dir.path}/old.sqlite');
    });

    Future<Map<String, bool>> columns(AppDatabase db, String table) => db
        .customSelect('PRAGMA table_info($table)')
        .map(
          (row) =>
              MapEntry(row.read<String>('name'), row.read<int>('notnull') == 1),
        )
        .get()
        .then(Map.fromEntries);

    /// Builds the current schema, then takes it back to version 6, before
    /// SMS capture.
    Future<AppDatabase> version6() async {
      final old = AppDatabase(NativeDatabase(file));
      await old.customStatement('DROP TABLE review_items');
      await old.customStatement('DROP INDEX accounts_institution');
      await old.customStatement(
        'ALTER TABLE accounts DROP COLUMN institution_id',
      );
      await old.customStatement('DROP INDEX transactions_dedupe');
      for (final column in [
        'counterparty_name',
        'dedupe_key',
        'balance_after_minor',
      ]) {
        await old.customStatement(
          'ALTER TABLE transactions DROP COLUMN $column',
        );
      }
      await old.customStatement('PRAGMA user_version = 6');
      return old;
    }

    /// Takes the schema back to version 5, before the debt planner.
    Future<AppDatabase> version5() async {
      final old = await version6();
      await old.customStatement('DROP TABLE debt_instalments');
      await old.customStatement('DROP TABLE debts');
      await old.customStatement(
        'CREATE TABLE debts ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'lender TEXT NOT NULL, type TEXT NOT NULL, '
        "currency TEXT NOT NULL DEFAULT 'KES', "
        'starting_balance_minor INTEGER NOT NULL, '
        'annual_rate_basis_points INTEGER NULL, '
        'minimum_payment_minor INTEGER NOT NULL DEFAULT 0, '
        'planned_payment_minor INTEGER NULL, '
        'is_formal INTEGER NOT NULL DEFAULT 1)',
      );
      await old.customStatement('PRAGMA user_version = 5');
      return old;
    }

    /// Takes the schema back to version 4, before the My accounts tables.
    Future<AppDatabase> version4() async {
      final old = await version5();
      await old.customStatement('DROP TABLE selected_institutions');
      await old.customStatement('DROP TABLE app_settings');
      await old.customStatement('PRAGMA user_version = 4');
      return old;
    }

    /// Takes the schema back to version 3, before categories were seeded.
    Future<AppDatabase> version3() async {
      final old = await version4();
      await old.customStatement('DELETE FROM categories');
      await old.customStatement('DROP INDEX categories_key');
      await old.customStatement('ALTER TABLE categories DROP COLUMN key');
      await old.customStatement('DROP INDEX transactions_counterparty');
      await old.customStatement(
        'ALTER TABLE transactions DROP COLUMN counterparty_kind',
      );
      await old.customStatement(
        'ALTER TABLE transactions DROP COLUMN counterparty_value',
      );
      await old.customStatement('DROP TABLE payee_identifiers');
      await old.customStatement('DROP TABLE payees');
      await old.customStatement(
        'CREATE TABLE payees ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'display_name TEXT NOT NULL, '
        'default_category_id INTEGER NULL REFERENCES categories (id), '
        'leak_type TEXT NULL)',
      );
      await old.customStatement(
        'CREATE TABLE payee_identifiers ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'payee_id INTEGER NOT NULL REFERENCES payees (id) ON DELETE CASCADE, '
        'kind TEXT NOT NULL, value TEXT NOT NULL, UNIQUE (kind, value))',
      );
      await old.customStatement('PRAGMA user_version = 3');
      return old;
    }

    Future<int> userVersion(AppDatabase db) => db
        .customSelect('PRAGMA user_version')
        .map((row) => row.read<int>('user_version'))
        .getSingle();

    Future<List<String>> tableNames(AppDatabase db) => db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row.read<String>('name'))
        .get();

    test('migrates a version 1 database to the current schema', () async {
      final old = await version3();
      await old.customStatement('ALTER TABLE transactions DROP COLUMN kind');
      await old.customStatement(
        'ALTER TABLE transactions DROP COLUMN fee_minor',
      );
      await old.customStatement('DROP TABLE budget_snapshots');
      await old.customStatement(
        'CREATE TABLE budget_snapshots ('
        'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        'month INTEGER NOT NULL, '
        'category_id INTEGER NOT NULL REFERENCES categories (id), '
        'planned_minor INTEGER NOT NULL, actual_minor INTEGER NOT NULL, '
        'frozen_at INTEGER NOT NULL, UNIQUE (month, category_id))',
      );
      await old.customStatement(
        'INSERT INTO categories (id, name, type, is_daily_spending) '
        "VALUES (1, 'Rent', 'expense', 0)",
      );
      await old.customStatement(
        'INSERT INTO budget_snapshots '
        '(month, category_id, planned_minor, actual_minor, frozen_at) '
        'VALUES (202609, 1, 100, 90, 0)',
      );
      await old.customStatement('PRAGMA user_version = 1');
      await old.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(
        (await columns(db, 'transactions')).keys,
        containsAll(['kind', 'fee_minor']),
      );
      expect((await columns(db, 'budget_snapshots'))['category_id'], isFalse);
      final kept = await db.select(db.budgetSnapshots).getSingle();
      expect(kept.plannedMinor, 100);
      expect(await userVersion(db), 10);
      expect(
        await tableNames(db),
        containsAll([
          'selected_institutions',
          'app_settings',
          'debt_instalments',
          'review_items',
        ]),
      );
      expect((await columns(db, 'debts')).keys, contains('balance_minor'));
    });

    test('migrates a version 3 database: payees, keys and seeds', () async {
      final old = await version3();
      await old.customStatement(
        'INSERT INTO categories (id, name, type, is_daily_spending) '
        "VALUES (1, 'groceries  and Household', 'expense', 1)",
      );
      await old.customStatement(
        'INSERT INTO payees (id, display_name, default_category_id, leak_type) '
        "VALUES (1, 'Test Grocer', 1, NULL), (2, 'Test Friend', NULL, 'friends')",
      );
      await old.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(
        (await columns(db, 'transactions')).keys,
        containsAll(['counterparty_kind', 'counterparty_value']),
      );
      expect((await columns(db, 'payees'))['leak_type'], isTrue);

      final payees = await (db.select(
        db.payees,
      )..orderBy([(p) => OrderingTerm(expression: p.id)])).get();
      expect(payees.map((p) => p.leakType), [LeakType.none, LeakType.friends]);
      expect(payees.first.defaultCategoryId, 1);

      final categories = await db.select(db.categories).get();
      expect(categories, hasLength(defaultCategories.length));
      final mine = categories.singleWhere((c) => c.id == 1);
      expect(mine.key, isNull);
      expect(categories.where((c) => c.key == 'groceries'), isEmpty);
      expect(
        categories.where((c) => c.key == 'salary').single.type,
        CategoryType.income,
      );
    });

    test('migrates a version 4 database: My accounts tables', () async {
      final old = await version4();
      final groceries = await (old.select(
        old.categories,
      )..where((c) => c.key.equals('groceries'))).getSingle();
      await old.customStatement(
        'INSERT INTO payees (id, display_name, default_category_id, leak_type) '
        "VALUES (1, 'Test Grocer', ${groceries.id}, 'none')",
      );
      final categoryCount = (await old.select(old.categories).get()).length;
      await old.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(await userVersion(db), 10);

      final institutions = DriftInstitutionsRepository(db);
      await institutions.setSelected('mpesa', selected: true);
      await DriftOnboardingRepository(db).markComplete();
      expect(await institutions.selectedIds(), {'mpesa'});
      expect(await DriftOnboardingRepository(db).isComplete(), isTrue);

      final payee = await db.select(db.payees).getSingle();
      expect(payee.displayName, 'Test Grocer');
      expect(payee.defaultCategoryId, groceries.id);
      expect(await db.select(db.categories).get(), hasLength(categoryCount));
    });

    test('migrates a version 5 database: the debt planner', () async {
      final old = await version5();
      await old.customStatement(
        'INSERT INTO debts (id, lender, type, starting_balance_minor) '
        "VALUES (1, 'Test Bank', 'bankLoan', 50000)",
      );
      await old.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(await userVersion(db), 10);
      expect(
        (await columns(db, 'debts')).keys,
        containsAll([
          'balance_minor',
          'balance_as_of',
          'payee_id',
          'custom_order',
        ]),
      );
      expect(
        (await columns(db, 'debt_instalments')).keys,
        contains('due_date'),
      );
      expect(await tableNames(db), contains('review_items'));
      final kept = await db.select(db.debts).getSingle();
      expect(kept.startingBalanceMinor, 50000);
      expect(kept.balanceMinor, isNull);
    });

    test('migrates a version 6 database: SMS capture', () async {
      final old = await version6();
      await old.customStatement(
        'INSERT INTO accounts (id, name, type, currency, opening_balance_minor, '
        "opening_date) VALUES (1, 'Cash', 'cash', 'KES', 0, 0)",
      );
      await old.customStatement(
        'INSERT INTO transactions (account_id, occurred_at, amount_minor, '
        "direction, fee_minor, currency, source) VALUES (1, 0, 5000, 'outflow', "
        "0, 'KES', 'manual')",
      );
      await old.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(await userVersion(db), 10);
      expect(await tableNames(db), contains('review_items'));
      expect(
        (await columns(db, 'transactions')).keys,
        containsAll(['counterparty_name', 'dedupe_key', 'balance_after_minor']),
      );

      final kept = await db.select(db.transactions).getSingle();
      expect(kept.amountMinor, 5000);
      expect(kept.dedupeKey, isNull);

      final accounts = DriftAccountsRepository(db);
      Future<int> mpesa() => accounts.accountForInstitution(
        'mpesa',
        name: 'M-Pesa',
        type: AccountType.mpesa,
        openingDate: DateTime.utc(2026, 10),
      );
      final mpesaId = await mpesa();
      expect(mpesaId, isNot(1));
      expect(await mpesa(), mpesaId);

      final transactions = DriftTransactionsRepository(db);
      TransactionsCompanion sms() => TransactionsCompanion.insert(
        accountId: mpesaId,
        occurredAt: DateTime.utc(2026, 10, 3),
        amountMinor: 100,
        direction: TransactionDirection.outflow,
        source: TransactionSource.sms,
        dedupeKey: const Value('TEST000001|100|2026-10-03T00:00Z'),
      );
      expect(await transactions.addNew([sms(), sms()]), 1);
      await expectLater(
        db.into(db.transactions).insert(sms()),
        throwsA(isA<SqliteException>()),
        reason: 'the dedupe index is unique per account',
      );
    });

    test('migrates a version 9 database: statement import records', () async {
      final old = AppDatabase(NativeDatabase(file));
      for (final column in [
        'institution_id',
        'opening_balance_minor',
        'transaction_count',
        'added_count',
        'duplicate_count',
        'unread_count',
        'result',
      ]) {
        await old.customStatement('ALTER TABLE imports DROP COLUMN $column');
      }
      await old.customStatement(
        'INSERT INTO accounts (id, name, type, currency, opening_balance_minor, '
        "opening_date) VALUES (1, 'M-Pesa', 'mpesa', 'KES', 0, 0)",
      );
      await old.customStatement(
        'INSERT INTO imports (account_id, file_hash, period_start, period_end, '
        "imported_at) VALUES (1, 'abc', 0, 0, 0)",
      );
      await old.customStatement('PRAGMA user_version = 9');
      await old.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(await userVersion(db), 10);
      final kept = await db.select(db.imports).getSingle();
      expect(kept.fileHash, 'abc');
      expect(kept.transactionCount, 0);
      expect(kept.institutionId, isNull);
      expect(kept.result, isNull);
    });

    test('the statement import step is safe to run twice', () async {
      final current = AppDatabase(NativeDatabase(file));
      await current.customStatement('PRAGMA user_version = 9');
      await current.close();

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      expect(await userVersion(db), 10);
      expect(
        (await columns(db, 'imports')).keys,
        containsAll(['institution_id', 'transaction_count', 'result']),
      );
    });

    test(
      'the debt planner and SMS capture steps are safe to run twice',
      () async {
        final current = AppDatabase(NativeDatabase(file));
        await current.customStatement(
          'INSERT INTO debts (id, lender, type, starting_balance_minor) '
          "VALUES (1, 'Test Bank', 'bankLoan', 50000)",
        );
        await current.customStatement(
          'INSERT INTO debt_instalments (debt_id, due_date, amount_minor) '
          'VALUES (1, 0, 100)',
        );
        await current.customStatement(
          'INSERT INTO review_items (institution_id, sender, received_at, '
          "message_hash, body, reason) VALUES ('mpesa', 'MPESA', 0, 'h', 'b', 'r')",
        );
        await current.customStatement('PRAGMA user_version = 5');
        await current.close();

        final db = AppDatabase(NativeDatabase(file));
        addTearDown(db.close);
        expect(await userVersion(db), 10);
        expect(await db.select(db.debts).get(), hasLength(1));
        expect(await db.select(db.debtInstalments).get(), hasLength(1));
        expect(await db.select(db.reviewItems).get(), hasLength(1));
      },
    );
  });
}
