import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/balances_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/reader/message_reading.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';
import 'package:pesaclarity/src/features/review/application/review_draft.dart';

import '../domain/fixtures.dart';
import '../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late DriftTransactionsRepository transactions;
  late DriftBalancesRepository balances;
  late int kcb;
  late int mpesa;

  setUp(() async {
    db = openTestDatabase();
    transactions = DriftTransactionsRepository(db);
    balances = DriftBalancesRepository(db);
    Future<int> account(String name, AccountType type) => db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: name,
            type: type,
            openingDate: eat(2026, 11, 1, 0),
          ),
        );
    kcb = await account('KCB', AccountType.bank);
    mpesa = await account('M-Pesa', AccountType.mpesa);
  });

  var n = 0;
  TransactionsCompanion tx(
    int accountId,
    DateTime at,
    int amount,
    TransactionDirection direction, {
    TransactionKind kind = TransactionKind.bank,
    int fee = 0,
  }) => TransactionsCompanion.insert(
    accountId: accountId,
    occurredAt: at,
    amountMinor: amount,
    direction: direction,
    kind: Value(kind),
    feeMinor: Value(fee),
    source: TransactionSource.sms,
    dedupeKey: Value('k${n++}'),
  );

  Future<Map<int, TransactionRecord>> all() async => {
    for (final r in await db.select(db.transactions).get()) r.id: r,
  };

  test('new messages pair with their other side as they arrive', () async {
    await transactions.addNew([
      tx(kcb, eat(2026, 11, 14, 10), kes(5030), TransactionDirection.outflow),
    ]);
    expect((await all()).values.single.transferPairId, isNull);
    await transactions.addNew([
      tx(
        mpesa,
        eat(2026, 11, 14, 10, 4),
        kes(5000),
        TransactionDirection.inflow,
        kind: TransactionKind.received,
      ),
    ]);
    final rows = (await all()).values.toList();
    expect(rows.map((r) => r.transferPairId), [rows[1].id, rows[0].id]);
  });

  test(
    'unmatching declines the pair, and pairing never makes it again',
    () async {
      await transactions.addNew([
        tx(kcb, eat(2026, 11, 14, 10), kes(500), TransactionDirection.outflow),
        tx(
          mpesa,
          eat(2026, 11, 14, 10, 1),
          kes(500),
          TransactionDirection.inflow,
        ),
      ]);
      final out = (await all()).values.first;
      await transactions.unmatch(out.id);
      expect(await transactions.pairOwnTransfers(), 0);
      expect(
        (await all()).values.every((r) => r.transferPairId == null),
        isTrue,
      );
      expect(await transactions.declinedTransfers(), hasLength(1));
    },
  );

  test('a named transfer waits for its side, up to three days', () async {
    final out = await transactions.add(
      tx(kcb, eat(2026, 11, 14, 10), kes(700), TransactionDirection.outflow),
    );
    await transactions.setTransferAccount(out, mpesa);
    expect((await all())[out]!.transferPairId, isNull);
    await transactions.addNew([
      tx(mpesa, eat(2026, 11, 16, 9), kes(700), TransactionDirection.inflow),
    ]);
    expect((await all())[out]!.transferPairId, isNotNull);
  });

  test(
    'a balance set by hand is a visible correction and a checkpoint',
    () async {
      await transactions.addNew([
        tx(kcb, eat(2026, 11, 2), kes(100), TransactionDirection.inflow),
      ]);
      final id = await balances.setBalance(
        kcb,
        statedMinor: kes(50),
        differenceMinor: -kes(50),
        at: eat(2026, 11, 14),
        currency: 'KES',
      );
      final entries = await transactions.ledgerEntries(
        from: eat(2026, 11, 1, 0),
        to: eat(2026, 11, 15),
      );
      final opening = AccountOpening(
        id: kcb,
        type: AccountType.bank,
        openingBalanceMinor: 0,
        openingDate: eat(2026, 11, 1, 0),
      );
      expect(balanceAt(opening, entries, at: eat(2026, 11, 15)), kes(50));
      await balances.undoCorrection(id);
      final after = await transactions.ledgerEntries(
        from: eat(2026, 11, 1, 0),
        to: eat(2026, 11, 15),
      );
      expect(balanceAt(opening, after, at: eat(2026, 11, 15)), kes(100));
    },
  );

  test('removing a copy keeps its tags on the one kept', () async {
    await transactions.addNew([
      tx(mpesa, eat(2026, 11, 2), kes(80), TransactionDirection.outflow),
      tx(mpesa, eat(2026, 11, 2), kes(80), TransactionDirection.outflow),
    ]);
    final [kept, copy] = (await all()).keys.toList();
    final tag = await db
        .into(db.tags)
        .insert(TagsCompanion.insert(name: 'Trip'));
    await db
        .into(db.transactionTags)
        .insert(
          TransactionTagsCompanion.insert(transactionId: copy, tagId: tag),
        );
    await balances.removeCopy(copy, keptId: kept);
    expect((await all()).keys, [kept]);
    expect(
      (await db.select(db.transactionTags).get()).single.transactionId,
      kept,
    );
  });

  test('an account without messages starts from what it holds', () async {
    final id = await balances.addAccount(
      name: 'Cash',
      type: AccountType.cash,
      currency: 'KES',
      balanceMinor: kes(100),
      at: eat(2026, 11, 14),
    );
    final row = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(id))).getSingle();
    expect(row.openingBalanceMinor, kes(100));
    expect(row.institutionId, isNull);
  });

  test('existing history pairs once after the update', () async {
    // Stored before pairing ran: straight into the table.
    for (final row in [
      tx(kcb, eat(2026, 10, 3, 9), kes(900), TransactionDirection.outflow),
      tx(mpesa, eat(2026, 10, 3, 9, 2), kes(900), TransactionDirection.inflow),
    ]) {
      await db.into(db.transactions).insert(row);
    }
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    await container.read(pairHistoryOnceProvider.future);
    expect((await all()).values.every((r) => r.transferPairId != null), isTrue);
    final setting = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('ledger.ownTransfersPaired'))).getSingle();
    expect(setting.value, contains('version'));
  });

  test('a balance from checking a message is stored as a claim', () {
    const draft = ReviewDraft(
      kind: MessageKind.moneyOut,
      amountMinor: 2000,
      balanceMinor: 3800000,
    );
    final row = draft.toTransaction(
      accountId: kcb,
      receivedAt: eat(2026, 11, 14),
      messageHash: 'h',
      currency: 'KES',
    );
    expect(row.balanceAfterMinor.present, isFalse);
    expect(row.claimedBalanceMinor.value, 3800000);
  });
}
