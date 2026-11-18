import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';

import '../domain/fixtures.dart';
import '../helpers/test_app.dart';

/// ledgerEntries reads rows with plain SQL: every column must come through
/// as drift's typed read would give it.
void main() {
  late AppDatabase db;
  late DriftTransactionsRepository repo;
  late int mpesa;
  late int bank;

  setUp(() async {
    db = openTestDatabase();
    repo = DriftTransactionsRepository(db);
    Future<int> account(String name, AccountType type) => db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: name,
            type: type,
            openingDate: eat(2026, 1, 1, 0),
          ),
        );
    mpesa = await account('M-Pesa', AccountType.mpesa);
    bank = await account('Bank', AccountType.bank);
  });

  test('every column reads as the typed record would', () async {
    final food = (await (db.select(
      db.categories,
    )..where((c) => c.isDailySpending.equals(true))).get()).first;
    final payee = await db
        .into(db.payees)
        .insert(
          PayeesCompanion.insert(
            displayName: 'Example Grocers',
            defaultCategoryId: Value(food.id),
            leakType: const Value(LeakType.lifestyle),
          ),
        );
    final tag = await db
        .into(db.tags)
        .insert(TagsCompanion.insert(name: 'Trip'));
    final id = await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: mpesa,
            occurredAt: eat(2026, 3, 4, 9, 30),
            amountMinor: 125000,
            direction: TransactionDirection.outflow,
            kind: const Value(TransactionKind.till),
            feeMinor: const Value(700),
            payeeId: Value(payee),
            counterpartyKind: const Value(PayeeIdentifierKind.phone),
            counterpartyValue: const Value('0700000000'),
            counterpartyName: const Value('Example Person'),
            item: const Value('Weekly shop'),
            receiptNo: const Value('SYN0000001'),
            source: TransactionSource.sms,
            balanceAfterMinor: const Value(500000),
            claimedBalanceMinor: const Value(499000),
            owedAfterMinor: const Value(20000),
            owedDueAt: Value(eat(2026, 4, 4, 0)),
            transferAccountId: Value(bank),
            autoCategoryId: Value(food.id),
            autoCategorySource: const Value(SuggestionSource.rules),
            autoCategoryConfidence: const Value(0.75),
            readBy: const Value('0.3.0 mpesa@0.3.1'),
          ),
        );
    await db
        .into(db.transactionTags)
        .insert(TransactionTagsCompanion.insert(transactionId: id, tagId: tag));

    final e = (await repo.ledgerEntries(
      from: eat(2026, 3, 1),
      to: eat(2026, 4, 1),
    )).single;
    final record = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(id))).getSingle();

    expect(e.id, id);
    expect(e.accountId, mpesa);
    expect(e.occurredAt, record.occurredAt);
    expect(e.amountMinor, 125000);
    expect(e.direction, TransactionDirection.outflow);
    expect(e.kind, TransactionKind.till);
    expect(e.feeMinor, 700);
    expect(e.currency, 'KES');
    expect(e.payeeId, payee);
    expect(e.payeeName, 'Example Grocers');
    expect(e.leakType, LeakType.lifestyle);
    expect(e.categoryId, food.id);
    expect(e.isDailySpending, isTrue);
    expect(e.counterpartyKind, PayeeIdentifierKind.phone);
    expect(e.counterpartyValue, '0700000000');
    expect(e.counterpartyName, 'Example Person');
    expect(e.note, 'Weekly shop');
    expect(e.source, TransactionSource.sms);
    expect(e.balanceAfterMinor, 500000);
    expect(e.claimedBalanceMinor, 499000);
    expect(e.owedAfterMinor, 20000);
    expect(e.owedDueAt, record.owedDueAt);
    expect(e.transferAccountId, bank);
    expect(e.tagIds, {tag});

    final tagged = await repo.ledgerEntries(
      from: eat(2026, 3, 1),
      to: eat(2026, 4, 1),
      tagId: tag,
    );
    expect(tagged.map((e) => e.id), [id]);
    expect(
      await repo.ledgerEntries(
        from: eat(2026, 3, 1),
        to: eat(2026, 4, 1),
        tagId: tag + 1,
      ),
      isEmpty,
    );
  });

  test('from is inclusive, to exclusive; oldest first, then by id; '
      'accounts filter', () async {
    Future<int> add(int account, DateTime at) => db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: account,
            occurredAt: at,
            amountMinor: 100,
            direction: TransactionDirection.inflow,
            source: TransactionSource.manual,
          ),
        );
    final later = await add(mpesa, eat(2026, 5, 2));
    final atFrom = await add(bank, eat(2026, 5, 1));
    final sameTime = await add(mpesa, eat(2026, 5, 1));
    await add(mpesa, eat(2026, 5, 3));

    final all = await repo.ledgerEntries(
      from: eat(2026, 5, 1),
      to: eat(2026, 5, 3),
    );
    expect(all.map((e) => e.id), [atFrom, sameTime, later]);
    expect(all.first.kind, TransactionKind.bank);
    expect(all.first.payeeId, isNull);
    expect(all.first.tagIds, isEmpty);

    final mpesaOnly = await repo.ledgerEntries(
      from: eat(2026, 5, 1),
      to: eat(2026, 5, 3),
      accountIds: {mpesa},
    );
    expect(mpesaOnly.map((e) => e.id), [sameTime, later]);
  });
}
