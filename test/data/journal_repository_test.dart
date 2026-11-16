import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/balances_repository.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/books/books.dart';

import '../domain/fixtures.dart';
import '../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late JournalRepository journal;
  late DriftTransactionsRepository transactions;
  late int mpesa;
  late int kcb;
  late int groceries;
  late int rent;

  setUp(() async {
    db = openTestDatabase();
    journal = JournalRepository(db, clock: () => eat(2026, 12, 1));
    transactions = DriftTransactionsRepository(db);
    Future<int> account(String name, AccountType type, int balance) => db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: name,
            type: type,
            openingBalanceMinor: Value(balance),
            openingDate: eat(2026, 11, 1, 0),
          ),
        );
    mpesa = await account('M-Pesa', AccountType.mpesa, kes(1000));
    kcb = await account('KCB', AccountType.bank, kes(5000));
    final expenses = await (db.select(
      db.categories,
    )..where((c) => c.type.equalsValue(CategoryType.expense))).get();
    groceries = expenses[0].id;
    rent = expenses[1].id;
  });

  var n = 0;
  TransactionsCompanion tx(
    int accountId,
    DateTime at,
    int amount, {
    TransactionDirection direction = TransactionDirection.outflow,
    TransactionKind kind = TransactionKind.till,
    int? balance,
    int? category,
  }) => TransactionsCompanion.insert(
    accountId: accountId,
    occurredAt: at,
    amountMinor: amount,
    direction: direction,
    kind: Value(kind),
    source: TransactionSource.sms,
    dedupeKey: Value('k${n++}'),
    balanceAfterMinor: Value(balance),
    categoryOverrideId: Value(category),
  );

  Future<List<JournalEntryRow>> entriesFor(int transactionId) =>
      (db.select(db.journalEntries)..where(
            (e) =>
                e.sourceKind.equalsValue(JournalSource.transaction) &
                e.sourceId.equals(transactionId),
          ))
          .get();

  Future<Map<String, int>> postingsOf(int entryId) async => {
    for (final p in await (db.select(
      db.postings,
    )..where((p) => p.entryId.equals(entryId))).get())
      p.account: p.amountMinor,
  };

  Future<int> balanceOf(BookAccount account) async =>
      (await journal.balances())[(account, 'KES')] ?? 0;

  test('posts every transaction once; a second sync changes nothing', () async {
    await transactions.add(
      tx(mpesa, eat(2026, 11, 2), kes(300), category: groceries),
    );
    await transactions.add(
      tx(
        mpesa,
        eat(2026, 11, 3),
        kes(200),
        direction: TransactionDirection.inflow,
        kind: TransactionKind.received,
        balance: kes(900),
      ),
    );
    final first = await journal.sync();
    // Two transactions and two openings.
    expect(first.posted, 4);
    expect(first.reversed, 0);
    final second = await journal.sync();
    expect(second.changed, isFalse);
    expect(await journal.unbalanced(), isEmpty);
    expect(await balanceOf(BookAccount.money(mpesa)), kes(900));
    expect(await balanceOf(BookAccount.money(kcb)), kes(5000));
    expect(await journal.reconcile(at: eat(2026, 12, 1)), isEmpty);
  });

  test('recategorising reverses the entry and posts it anew', () async {
    final id = await transactions.add(
      tx(mpesa, eat(2026, 11, 2), kes(300), category: groceries),
    );
    await journal.sync();
    final before = (await entriesFor(id)).single;

    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(categoryOverrideId: Value(rent)),
    );
    final sync = await journal.sync();
    expect(sync.posted, 1);
    expect(sync.reversed, 1);

    final entries = await entriesFor(id);
    expect(entries, hasLength(3));
    final reversal = entries.singleWhere((e) => e.reverses == before.id);
    expect(reversal.occurredAt, before.occurredAt);
    expect(await postingsOf(reversal.id), {
      for (final MapEntry(:key, :value) in (await postingsOf(
        before.id,
      )).entries)
        key: -value,
    });
    final now = entries.singleWhere(
      (e) => e.id != before.id && e.reverses == null,
    );
    expect(await postingsOf(now.id), {
      BookAccount.category(rent, income: false).key: kes(300),
      BookAccount.money(mpesa).key: -kes(300),
    });
    // The old entry is still there, untouched.
    expect(await postingsOf(before.id), {
      BookAccount.category(groceries, income: false).key: kes(300),
      BookAccount.money(mpesa).key: -kes(300),
    });
    expect(await journal.unbalanced(), isEmpty);
    expect(await journal.reconcile(at: eat(2026, 12, 1)), isEmpty);
  });

  test('moving a transaction to another account moves its money', () async {
    final id = await transactions.add(
      tx(mpesa, eat(2026, 11, 2), kes(300), category: groceries),
    );
    await journal.sync();
    await DriftBalancesRepository(db).moveToAccount(id, kcb);
    await journal.sync();
    expect(await balanceOf(BookAccount.money(mpesa)), kes(1000));
    expect(await balanceOf(BookAccount.money(kcb)), kes(4700));
    expect(await journal.reconcile(at: eat(2026, 12, 1)), isEmpty);
  });

  test('matching and unmatching an own transfer reposts both halves', () async {
    final out = await transactions.add(
      tx(kcb, eat(2026, 11, 3, 10), kes(2000), kind: TransactionKind.bank),
    );
    final into = await transactions.add(
      tx(
        mpesa,
        eat(2026, 11, 3, 10, 1),
        kes(2000),
        direction: TransactionDirection.inflow,
        kind: TransactionKind.received,
      ),
    );
    await journal.sync();
    await transactions.match(out, into);
    await journal.sync();
    expect(await balanceOf(BookAccount.moneyInTransit), 0);
    expect(await balanceOf(BookAccount.uncategorisedSpending), 0);

    // Declined: each half counts as it reads, and stays apart.
    await transactions.unmatch(out);
    await journal.sync();
    expect(await balanceOf(BookAccount.moneyInTransit), 0);
    expect(await balanceOf(BookAccount.uncategorisedSpending), kes(2000));
    expect(await journal.unbalanced(), isEmpty);
  });

  test(
    'a correction posts to Balance corrections; undoing it reverses it',
    () async {
      final balances = DriftBalancesRepository(db);
      final id = await balances.setBalance(
        kcb,
        statedMinor: kes(4800),
        differenceMinor: -kes(200),
        at: eat(2026, 11, 10),
        currency: 'KES',
      );
      await journal.sync();
      expect(await balanceOf(BookAccount.money(kcb)), kes(4800));
      expect(await balanceOf(BookAccount.balanceCorrections), -kes(200));

      await balances.undoCorrection(id);
      final sync = await journal.sync();
      expect(sync.reversed, 1);
      expect(sync.posted, 0);
      expect(await balanceOf(BookAccount.money(kcb)), kes(5000));
      expect(await balanceOf(BookAccount.balanceCorrections), 0);
      expect(await entriesFor(id), hasLength(2));
    },
  );

  test('a space keeps its own journal', () async {
    final other = openTestDatabase();
    await transactions.add(tx(mpesa, eat(2026, 11, 2), kes(300)));
    await journal.sync();
    expect(await db.select(db.journalEntries).get(), isNotEmpty);
    expect(await other.select(other.journalEntries).get(), isEmpty);
  });

  test('the keeper posts new transactions and recategorising as they are '
      'written', () async {
    final keeper = JournalKeeper(db, journal: journal)..start();
    addTearDown(keeper.stop);
    final id = await transactions.add(
      tx(mpesa, eat(2026, 11, 2), kes(300), category: groceries),
    );
    // Let the change notice arrive, then the sync finish.
    await pumpEventQueue();
    await keeper.idle;
    expect(await entriesFor(id), hasLength(1));

    await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(categoryOverrideId: Value(rent)),
    );
    await pumpEventQueue();
    await keeper.idle;
    expect(await entriesFor(id), hasLength(3));
    expect(await journal.reconcile(at: eat(2026, 12, 1)), isEmpty);
  });
}
