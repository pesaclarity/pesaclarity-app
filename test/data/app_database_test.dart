import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/connection.dart';
import 'package:pesaclarity/src/data/database/database_key_store.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
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
  });
}
