// Stage 3 of the journal (decision 0018): every fix a person can make is
// an entry. Setting a balance, a cash count, a correction, unmatching and
// moving post reversing entries plus new ones, never an edit, and a
// rebuild from the records ends where the incremental path did.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/balances_repository.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/space_move_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/books/books.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/spaces/space_categories.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/space_manager.dart';

import '../domain/fixtures.dart';
import '../helpers/balance_oracle.dart';
import '../helpers/journal_history.dart';
import '../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late JournalRepository journal;
  late DriftTransactionsRepository transactions;
  late DriftBalancesRepository balances;
  late JournalLog log;
  late int mpesa;
  late int kcb;
  late int cash;
  final monthEnd = eat(2026, 12, 1, 0);

  Future<int> account(
    AppDatabase db,
    String name,
    AccountType type,
    int balance, {
    String? institution,
  }) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: name,
          type: type,
          openingBalanceMinor: Value(balance),
          openingDate: eat(2026, 11, 1, 0),
          institutionId: Value(institution),
        ),
      );

  setUp(() async {
    db = openTestDatabase();
    journal = JournalRepository(db, clock: () => monthEnd);
    transactions = DriftTransactionsRepository(db);
    balances = DriftBalancesRepository(db);
    log = JournalLog(db, journal);
    mpesa = await account(db, 'M-Pesa', AccountType.mpesa, kes(1000));
    kcb = await account(db, 'KCB', AccountType.bank, kes(20000));
    cash = await account(db, 'Cash', AccountType.cash, kes(500));
  });

  var n = 0;
  TransactionsCompanion tx(
    int accountId,
    DateTime at,
    int amount, {
    bool inflow = false,
    TransactionKind kind = TransactionKind.till,
    int fee = 0,
    int? balance,
    int? category,
    TransactionSource source = TransactionSource.sms,
  }) => TransactionsCompanion.insert(
    accountId: accountId,
    occurredAt: at,
    amountMinor: amount,
    direction: inflow
        ? TransactionDirection.inflow
        : TransactionDirection.outflow,
    kind: Value(kind),
    feeMinor: Value(fee),
    source: source,
    dedupeKey: Value('k${n++}'),
    balanceAfterMinor: Value(balance),
    categoryOverrideId: Value(category),
  );

  /// KCB sends [out] to M-Pesa, where [into] arrives a minute later.
  Future<(int, int)> transfer(
    int out,
    int into, {
    int day = 3,
    int fee = 0,
  }) async {
    final sent = await transactions.add(
      tx(
        kcb,
        eat(2026, 11, day, 10),
        out,
        kind: TransactionKind.bank,
        fee: fee,
      ),
    );
    final got = await transactions.add(
      tx(
        mpesa,
        eat(2026, 11, day, 10, 1),
        into,
        inflow: true,
        kind: TransactionKind.received,
      ),
    );
    return (sent, got);
  }

  Future<int> of(BookAccount a, {DateTime? at}) async =>
      (await journal.read()).balanceOf(a, currency: 'KES', at: at);

  Future<List<JournalEntryRow>> entriesFor(
    int sourceId, [
    JournalSource kind = JournalSource.transaction,
  ]) =>
      (db.select(db.journalEntries)
            ..where(
              (e) =>
                  e.sourceKind.equalsValue(kind) & e.sourceId.equals(sourceId),
            )
            ..orderBy([(e) => OrderingTerm.asc(e.id)]))
          .get();

  Future<Map<String, int>> postingsOf(int entryId) async => {
    for (final p in await (db.select(
      db.postings,
    )..where((p) => p.entryId.equals(entryId))).get())
      p.account: p.amountMinor,
  };

  /// The one entry of [sourceId] that is neither reversed nor a reversal.
  Future<Map<String, int>> live(
    int sourceId, [
    JournalSource kind = JournalSource.transaction,
  ]) async {
    final all = await entriesFor(sourceId, kind);
    final reversed = {for (final e in all) ?e.reverses};
    final live = [
      for (final e in all)
        if (e.reverses == null && !reversed.contains(e.id)) e,
    ];
    return live.isEmpty ? const {} : postingsOf(live.single.id);
  }

  /// After a fix: nothing stored was edited, every entry balances, a
  /// rebuild changes nothing, and money and Fuliza owed are what the
  /// records add up to.
  Future<void> settled() async {
    await log.check();
    final rebuilt = await journal.rebuild();
    expect(rebuilt.changed, isFalse, reason: 'a rebuild after the fix');
    expect(await reconcileWithOracle(db, at: monthEnd), isEmpty);
  }

  group('a fix is an entry', () {
    test('Set the balance posts a correction against Balance corrections, '
        'and setting it again posts another', () async {
      await transactions.add(tx(kcb, eat(2026, 11, 2), kes(300)));
      await log.check();
      final first = await balances.setBalance(
        kcb,
        statedMinor: kes(19000),
        differenceMinor: -kes(700),
        at: eat(2026, 11, 10),
        currency: 'KES',
      );
      await settled();
      expect(await of(BookAccount.money(kcb)), kes(19000));
      expect(await of(BookAccount.balanceCorrections), -kes(700));
      expect(await live(first), {
        BookAccount.money(kcb).key: -kes(700),
        BookAccount.balanceCorrections.key: kes(700),
      });

      final second = await balances.setBalance(
        kcb,
        statedMinor: kes(19250),
        differenceMinor: kes(250),
        at: eat(2026, 11, 12),
        currency: 'KES',
      );
      await settled();
      expect(await of(BookAccount.money(kcb)), kes(19250));
      expect(await of(BookAccount.balanceCorrections), -kes(450));
      // The first correction's entry stands as posted.
      expect(await entriesFor(first), hasLength(1));
      expect(await entriesFor(second), hasLength(1));
    });

    test('Set the balance on M-Pesa below zero empties the wallet and owes '
        'the rest to Fuliza', () async {
      await transactions.add(
        tx(mpesa, eat(2026, 11, 2), kes(100), balance: kes(900)),
      );
      // The app shows 900; M-Pesa is really 300 into Fuliza.
      final id = await balances.setBalance(
        mpesa,
        statedMinor: -kes(300),
        differenceMinor: -kes(1200),
        at: eat(2026, 11, 10),
        currency: 'KES',
      );
      await settled();
      expect(await of(BookAccount.money(mpesa)), 0);
      expect(await of(BookAccount.fulizaOwed(mpesa)), kes(300));
      expect(await live(id), {
        BookAccount.money(mpesa).key: -kes(900),
        BookAccount.fulizaOwed(mpesa).key: -kes(300),
        BookAccount.balanceCorrections.key: kes(1200),
      });
    });

    test('a message that arrives later, dated before a balance that was '
        'set, reverses the correction and posts it anew', () async {
      await transactions.add(
        tx(kcb, eat(2026, 11, 2), kes(300), balance: kes(19700)),
      );
      final id = await balances.setBalance(
        kcb,
        statedMinor: kes(18700),
        differenceMinor: -kes(1000),
        at: eat(2026, 11, 10),
        currency: 'KES',
      );
      await log.check();
      final before = (await entriesFor(id)).single;
      // 400 of the 1,000 turns out to be a payment whose message was late.
      await transactions.add(tx(kcb, eat(2026, 11, 5), kes(400)));
      await settled();
      expect(await of(BookAccount.money(kcb)), kes(18700));
      expect(await of(BookAccount.balanceCorrections), -kes(600));
      final entries = await entriesFor(id);
      expect(entries, hasLength(3));
      expect(entries[0].id, before.id);
      expect(entries[1].reverses, before.id);
      expect(await postingsOf(before.id), {
        BookAccount.money(kcb).key: -kes(1000),
        BookAccount.balanceCorrections.key: kes(1000),
      });
      expect(await postingsOf(entries[2].id), {
        BookAccount.money(kcb).key: -kes(600),
        BookAccount.balanceCorrections.key: kes(600),
      });
    });

    test('with no reported balance before it, a balance set by hand is '
        'where the account starts: an entry added later, dated before it, '
        'moves the opening and leaves the correction', () async {
      await transactions.add(
        tx(cash, eat(2026, 11, 4), kes(120), source: TransactionSource.manual),
      );
      final id = await balances.setBalance(
        cash,
        statedMinor: kes(350),
        differenceMinor: -kes(30),
        at: eat(2026, 11, 6),
        currency: 'KES',
      );
      await log.check();
      // A purchase remembered later.
      await transactions.add(
        tx(cash, eat(2026, 11, 5), kes(20), source: TransactionSource.manual),
      );
      await settled();
      expect(await of(BookAccount.money(cash)), kes(350));
      expect(await entriesFor(id), hasLength(1));
      expect(await live(id), {
        BookAccount.money(cash).key: -kes(30),
        BookAccount.balanceCorrections.key: kes(30),
      });
      // The opening is reversed and posted as 520, as the first reported
      // balance of an account is (see `postJournal`).
      expect(await entriesFor(cash, JournalSource.opening), hasLength(3));
      expect(await live(cash, JournalSource.opening), {
        BookAccount.money(cash).key: kes(520),
        BookAccount.openingBalances.key: -kes(520),
      });
    });

    test('undoing a correction reverses it; both entries stay', () async {
      final id = await balances.setBalance(
        kcb,
        statedMinor: kes(19000),
        differenceMinor: -kes(1000),
        at: eat(2026, 11, 10),
        currency: 'KES',
      );
      await log.check();
      await balances.undoCorrection(id);
      await settled();
      expect(await of(BookAccount.money(kcb)), kes(20000));
      expect(await of(BookAccount.balanceCorrections), 0);
      final entries = await entriesFor(id);
      expect(entries, hasLength(2));
      expect(entries[1].reverses, entries[0].id);
      expect(await live(id), isEmpty);
    });

    test('counting cash is a correction on the cash account', () async {
      await transactions.add(
        tx(cash, eat(2026, 11, 4), kes(120), source: TransactionSource.manual),
      );
      final id = await balances.setBalance(
        cash,
        statedMinor: kes(350),
        differenceMinor: -kes(30),
        at: eat(2026, 11, 6),
        currency: 'KES',
      );
      await settled();
      expect(await of(BookAccount.money(cash)), kes(350));
      expect(await live(id), {
        BookAccount.money(cash).key: -kes(30),
        BookAccount.balanceCorrections.key: kes(30),
      });
    });

    test('a cash count booked at Close the day posts the difference '
        'against Cash difference', () async {
      final now = eat(2026, 11, 5, 19);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => now),
        ],
      );
      addTearDown(container.dispose);
      final sales = container.read(salesControllerProvider);
      // The drawer holds 80 less than the records say.
      await sales.bookCashDifference(-kes(80));
      await settled();
      final short = await db.select(db.transactions).getSingle();
      final category = await (db.select(
        db.categories,
      )..where((c) => c.key.equals(cashDifferenceSeed.key))).getSingle();
      expect(short.accountId, cash);
      expect(await live(short.id), {
        BookAccount.money(cash).key: -kes(80),
        BookAccount.category(category.id, income: false).key: kes(80),
      });
      // The next count finds 30 more: the cost comes down, nothing is
      // edited.
      await sales.bookCashDifference(kes(30));
      await settled();
      expect(await of(BookAccount.money(cash)), kes(450));
      expect(
        await of(BookAccount.category(category.id, income: false)),
        kes(50),
      );
      expect(await entriesFor(short.id), hasLength(1));
    });

    test('a gap moves from Not yet sorted to Balance corrections when the '
        'person adds a correction, and back when they undo it', () async {
      await transactions.add(
        tx(mpesa, eat(2026, 11, 2), kes(100), balance: kes(900)),
      );
      // 50 short: a message never came.
      final late = await transactions.add(
        tx(mpesa, eat(2026, 11, 4), kes(100), balance: kes(750)),
      );
      await log.check();
      expect(await of(BookAccount.notYetSorted), -kes(50));
      expect(await live(late, JournalSource.balanceDifference), {
        BookAccount.money(mpesa).key: -kes(50),
        BookAccount.notYetSorted.key: kes(50),
      });

      final id = await balances.addGapCorrection(
        mpesa,
        differenceMinor: -kes(50),
        at: eat(2026, 11, 3),
        currency: 'KES',
      );
      await settled();
      expect(await of(BookAccount.notYetSorted), 0);
      expect(await of(BookAccount.balanceCorrections), -kes(50));
      expect(await of(BookAccount.money(mpesa)), kes(750));
      // The gap's entry is reversed, not removed.
      final gap = await entriesFor(late, JournalSource.balanceDifference);
      expect(gap, hasLength(2));
      expect(gap[1].reverses, gap[0].id);

      await balances.undoCorrection(id);
      await settled();
      expect(await of(BookAccount.notYetSorted), -kes(50));
      expect(await of(BookAccount.balanceCorrections), 0);
      expect(
        await entriesFor(late, JournalSource.balanceDifference),
        hasLength(3),
      );
    });

    test('Fuliza is paid posts what was owed against Balance corrections; '
        'undoing it reverses it', () async {
      await transactions.add(
        tx(mpesa, eat(2026, 11, 2, 9), kes(100), balance: kes(900)),
      );
      await transactions.add(
        tx(mpesa, eat(2026, 11, 2), kes(1400), balance: 0),
      );
      await log.check();
      // 500 past the wallet, plus the access fee.
      expect(await of(BookAccount.fulizaOwed(mpesa)), kes(505));
      final id = await balances.markFulizaPaid(
        mpesa,
        walletMinor: 0,
        owedMinor: kes(505),
        at: eat(2026, 11, 5),
        currency: 'KES',
      );
      await settled();
      expect(await of(BookAccount.fulizaOwed(mpesa)), 0);
      expect(await live(id), {
        BookAccount.fulizaOwed(mpesa).key: kes(505),
        BookAccount.balanceCorrections.key: -kes(505),
      });
      await balances.undoCorrection(id);
      await settled();
      expect(await of(BookAccount.fulizaOwed(mpesa)), kes(505));
      expect(await entriesFor(id), hasLength(2));
    });

    test('a Fuliza repayment added from a gap posts against Fuliza '
        'owed', () async {
      await transactions.add(
        tx(mpesa, eat(2026, 11, 2, 9), kes(100), balance: kes(900)),
      );
      await transactions.add(
        tx(mpesa, eat(2026, 11, 2), kes(1400), balance: 0),
      );
      final id = await balances.addFulizaRepayment(
        mpesa,
        amountMinor: kes(505),
        at: eat(2026, 11, 5),
        currency: 'KES',
      );
      await settled();
      expect(await of(BookAccount.fulizaOwed(mpesa)), 0);
      expect((await live(id))[BookAccount.fulizaOwed(mpesa).key], kes(505));
    });

    test('moving a transaction to another account reverses its entry and '
        'posts it there, with the gap it explains', () async {
      await transactions.add(
        tx(mpesa, eat(2026, 11, 2), kes(100), balance: kes(900)),
      );
      // Read onto KCB by mistake: M-Pesa's next balance is 250 short.
      final wrong = await transactions.add(tx(kcb, eat(2026, 11, 3), kes(250)));
      final next = await transactions.add(
        tx(mpesa, eat(2026, 11, 4), kes(100), balance: kes(550)),
      );
      await log.check();
      expect(await of(BookAccount.notYetSorted), -kes(250));
      final before = (await entriesFor(wrong)).single;

      await balances.moveToAccount(wrong, mpesa);
      await settled();
      expect(await of(BookAccount.money(kcb)), kes(20000));
      expect(await of(BookAccount.money(mpesa)), kes(550));
      expect(await of(BookAccount.notYetSorted), 0);
      final entries = await entriesFor(wrong);
      expect(entries, hasLength(3));
      expect(entries[1].reverses, before.id);
      expect(entries[1].accountId, kcb);
      expect(entries[2].accountId, mpesa);
      expect(await postingsOf(before.id), {
        BookAccount.money(kcb).key: -kes(250),
        BookAccount.uncategorisedSpending.key: kes(250),
      });
      expect(await postingsOf(entries[2].id), {
        BookAccount.money(mpesa).key: -kes(250),
        BookAccount.uncategorisedSpending.key: kes(250),
      });
      // The gap it explains is reversed too.
      final gap = await entriesFor(next, JournalSource.balanceDifference);
      expect(gap, hasLength(2));
      expect(gap[1].reverses, gap[0].id);
    });

    test('removing a copy reverses its entry and leaves the one '
        'kept', () async {
      final kept = await transactions.add(
        tx(mpesa, eat(2026, 11, 2), kes(100)),
      );
      final copy = await transactions.add(
        tx(
          mpesa,
          eat(2026, 11, 2),
          kes(100),
          source: TransactionSource.statement,
        ),
      );
      await log.check();
      await balances.removeCopy(copy, keptId: kept);
      await settled();
      expect(await of(BookAccount.money(mpesa)), kes(900));
      expect(await entriesFor(copy), hasLength(2));
      expect(await entriesFor(kept), hasLength(1));
    });

    test('recategorising reverses the entry and posts it anew', () async {
      final expenses = await (db.select(
        db.categories,
      )..where((c) => c.type.equalsValue(CategoryType.expense))).get();
      final id = await transactions.add(
        tx(mpesa, eat(2026, 11, 2), kes(300), category: expenses[0].id),
      );
      await log.check();
      await (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(categoryOverrideId: Value(expenses[1].id)),
      );
      await settled();
      expect(await entriesFor(id), hasLength(3));
      expect(await live(id), {
        BookAccount.money(mpesa).key: -kes(300),
        BookAccount.category(expenses[1].id, income: false).key: kes(300),
      });
    });
  });

  group('moving to another space', () {
    late AppDatabase business;

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      business = AppDatabase(NativeDatabase.memory());
      addTearDown(business.close);
      await business.becomeSpace(SpaceKind.business);
    });

    test('reverses the entry here and posts one there: nothing posts across '
        'spaces', () async {
      final moves = DriftSpaceMoveRepository(
        db,
        (spaceId) async => (business, false),
      );
      final id = await transactions.add(
        tx(
          mpesa,
          eat(2026, 11, 3),
          kes(650),
          inflow: true,
          kind: TransactionKind.received,
        ),
      );
      await log.check();
      expect(await of(BookAccount.money(mpesa)), kes(1650));
      final there = JournalRepository(business, clock: () => monthEnd);
      final thereLog = JournalLog(business, there);
      await thereLog.check();
      final thereBefore = await journalRows(business);

      await moves.move(id, 'shop1');
      await settled();
      // Here: reversed, and the money is no longer counted.
      expect(await of(BookAccount.money(mpesa)), kes(1000));
      expect(await of(BookAccount.notYetSorted), 0);
      final entries = await entriesFor(id);
      expect(entries, hasLength(2));
      expect(entries[1].reverses, entries[0].id);

      // There: one new entry, in that space's own journal.
      await thereLog.check();
      final moved = await business.select(business.transactions).getSingle();
      final posted = await (business.select(
        business.journalEntries,
      )..where((e) => e.sourceId.equals(moved.id))).get();
      expect(
        posted.where((e) => e.sourceKind == JournalSource.transaction),
        hasLength(1),
      );
      expect(
        (await there.read()).balanceOf(
          BookAccount.money(moved.accountId),
          currency: 'KES',
        ),
        kes(650),
      );
      expect((await there.rebuild()).changed, isFalse);
      expectOnlyAppended(thereBefore, await journalRows(business));
      // No entry in either journal names the other space or its rows.
      expect(
        (await db.select(db.journalEntries).get()).map((e) => e.memo),
        everyElement(isNull),
      );
    });

    test('one half of an own transfer moved away leaves the other on its '
        'own, and the transfer no longer clears', () async {
      final moves = DriftSpaceMoveRepository(
        db,
        (spaceId) async => (business, false),
      );
      final (sent, got) = await transfer(kes(2030), kes(2000));
      await transactions.match(sent, got);
      await log.check();
      await moves.move(got, 'shop1');
      await settled();
      expect(await of(BookAccount.money(mpesa)), kes(1000));
      expect(await of(BookAccount.money(kcb)), kes(20000 - 2030));
      // KCB's side reads alone again: spending, nothing in transit.
      expect(await of(BookAccount.moneyInTransit), 0);
      expect(await of(BookAccount.fees), 0);
      expect(await of(BookAccount.uncategorisedSpending), kes(2030));
    });
  });

  group('Money in transit', () {
    test('clears when both sides match for the same amount', () async {
      final (sent, got) = await transfer(kes(2000), kes(2000));
      await transactions.match(sent, got);
      await settled();
      expect(await of(BookAccount.moneyInTransit), 0);
      expect(await of(BookAccount.fees), 0);
      expect(await of(BookAccount.uncategorisedSpending), 0);
      expect(await of(BookAccount.notYetSorted), 0);
    });

    test('clears with a fee the message printed', () async {
      final (sent, got) = await transfer(kes(2000), kes(2000), fee: kes(30));
      await transactions.match(sent, got);
      await settled();
      expect(await of(BookAccount.moneyInTransit), 0);
      expect(await of(BookAccount.fees), kes(30));
      expect(await of(BookAccount.money(kcb)), kes(20000 - 2030));
    });

    test('clears when less arrives than left: the difference is the '
        "transfer's fee", () async {
      final (sent, got) = await transfer(kes(2030), kes(2000));
      await transactions.match(sent, got);
      await settled();
      expect(await of(BookAccount.moneyInTransit), 0);
      expect(await of(BookAccount.fees), kes(30));
      expect(await of(BookAccount.money(kcb)), kes(20000 - 2030));
      expect(await of(BookAccount.money(mpesa)), kes(1000 + 2000));
      // While the money is on its way, only what will arrive is in transit.
      expect(
        await of(BookAccount.moneyInTransit, at: eat(2026, 11, 3, 10, 1)),
        kes(2000),
      );
    });

    test('a fee the message printed and a difference both count', () async {
      final (sent, got) = await transfer(kes(2030), kes(2000), fee: kes(20));
      await transactions.match(sent, got);
      await settled();
      expect(await of(BookAccount.moneyInTransit), 0);
      expect(await of(BookAccount.fees), kes(50));
      expect(await of(BookAccount.money(kcb)), kes(20000 - 2050));
    });

    test('messages pair as they arrive, and clear', () async {
      await transactions.addNew([
        tx(kcb, eat(2026, 11, 3, 10), kes(5040), kind: TransactionKind.bank),
      ]);
      await log.check();
      // Not known to be a transfer yet.
      expect(await of(BookAccount.moneyInTransit), 0);
      await transactions.addNew([
        tx(
          mpesa,
          eat(2026, 11, 3, 10, 4),
          kes(5000),
          inflow: true,
          kind: TransactionKind.received,
        ),
      ]);
      await settled();
      expect(await of(BookAccount.moneyInTransit), 0);
      expect(await of(BookAccount.fees), kes(40));
      expect(await of(BookAccount.uncategorisedSpending), 0);
    });

    test('more arriving than left is not yet sorted', () async {
      final (sent, got) = await transfer(kes(2000), kes(2030));
      await transactions.match(sent, got);
      await settled();
      expect(await of(BookAccount.moneyInTransit), 0);
      expect(await of(BookAccount.fees), 0);
      expect(await of(BookAccount.notYetSorted), kes(30));
    });

    test('a transfer the person named waits in transit, then clears with '
        'its fee when its side arrives', () async {
      final sent = await transactions.add(
        tx(kcb, eat(2026, 11, 3, 10), kes(2030), kind: TransactionKind.bank),
      );
      await transactions.setTransferAccount(sent, mpesa);
      await settled();
      expect(await of(BookAccount.moneyInTransit), kes(2030));
      await transactions.addNew([
        tx(
          mpesa,
          eat(2026, 11, 4, 9),
          kes(2000),
          inflow: true,
          kind: TransactionKind.received,
        ),
      ]);
      await settled();
      expect(await of(BookAccount.moneyInTransit), 0);
      expect(await of(BookAccount.fees), kes(30));
    });

    test('unmatching reverses the clearing: each side counts as it reads '
        'alone', () async {
      final (sent, got) = await transfer(kes(2030), kes(2000));
      await transactions.match(sent, got);
      await log.check();
      await transactions.unmatch(sent);
      await settled();
      expect(await of(BookAccount.moneyInTransit), 0);
      expect(await of(BookAccount.fees), 0);
      expect(await of(BookAccount.uncategorisedSpending), kes(2030));
      // Money in from someone not named.
      expect(await of(BookAccount.notYetSorted), kes(2000));
      expect(await entriesFor(sent), hasLength(3));
      expect(await entriesFor(got), hasLength(3));
      expect(await live(sent), {
        BookAccount.money(kcb).key: -kes(2030),
        BookAccount.uncategorisedSpending.key: kes(2030),
      });
    });

    test('a side that changes on its own reposts the clearing, though only '
        'its account changed', () async {
      final (sent, got) = await transfer(kes(2030), kes(2000));
      await transactions.match(sent, got);
      await log.check();
      expect(await of(BookAccount.fees), kes(30));
      // M-Pesa's side is read again as 2,010: only M-Pesa is marked.
      await (db.update(db.transactions)..where((t) => t.id.equals(got))).write(
        TransactionsCompanion(amountMinor: Value(kes(2010))),
      );
      expect(
        [for (final d in await db.select(db.journalDirty).get()) d.accountId],
        [mpesa],
      );
      await settled();
      expect(await of(BookAccount.moneyInTransit), 0);
      expect(await of(BookAccount.fees), kes(20));
      // And the other way: KCB's side alone.
      await (db.update(db.transactions)..where((t) => t.id.equals(sent))).write(
        TransactionsCompanion(amountMinor: Value(kes(2050))),
      );
      await settled();
      expect(await of(BookAccount.moneyInTransit), 0);
      expect(await of(BookAccount.fees), kes(40));
    });

    test('an account that changes for another reason leaves its transfers '
        'cleared, once', () async {
      final (sent, got) = await transfer(kes(2030), kes(2000));
      await transactions.match(sent, got);
      await log.check();
      final before = await journalRows(db);
      // A payment on M-Pesa: only M-Pesa is reposted.
      await transactions.add(tx(mpesa, eat(2026, 11, 8), kes(100)));
      await settled();
      final after = await journalRows(db);
      // One new entry, and nothing reversed.
      expect(after.entries.length, before.entries.length + 1);
      expect(await of(BookAccount.fees), kes(30));
      // The same for KCB.
      await transactions.add(tx(kcb, eat(2026, 11, 9), kes(100)));
      await settled();
      expect((await journalRows(db)).entries.length, after.entries.length + 1);
      expect(await of(BookAccount.fees), kes(30));
    });

    test('two currencies: each side waits in its own currency', () async {
      final usd = await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(
              name: 'KCB USD',
              type: AccountType.bank,
              currency: const Value('USD'),
              openingBalanceMinor: const Value(100000),
              openingDate: eat(2026, 11, 1, 0),
            ),
          );
      final sent = await transactions.add(
        tx(
          usd,
          eat(2026, 11, 3, 10),
          10000,
          kind: TransactionKind.bank,
        ).copyWith(currency: const Value('USD')),
      );
      final got = await transactions.add(
        tx(
          mpesa,
          eat(2026, 11, 3, 10, 1),
          kes(12900),
          inflow: true,
          kind: TransactionKind.received,
        ),
      );
      await transactions.match(sent, got);
      await settled();
      final read = await journal.read();
      expect(
        read.balanceOf(BookAccount.moneyInTransit, currency: 'USD'),
        10000,
      );
      expect(
        read.balanceOf(BookAccount.moneyInTransit, currency: 'KES'),
        -kes(12900),
      );
      expect(read.balanceOf(BookAccount.fees, currency: 'KES'), 0);
      expect(read.balanceOf(BookAccount.fees, currency: 'USD'), 0);
    });
  });

  group('rebuilding', () {
    /// Every balance in [db]'s journal at the end of each day of the
    /// month.
    Future<Map<String, int>> everyBalance(AppDatabase db) async {
      final repository = JournalRepository(db, clock: () => monthEnd);
      final out = <String, int>{};
      for (var day = 1; day <= 31; day++) {
        final at = eat(2026, 11, day, 23, 59);
        for (final MapEntry(key: (account, currency), :value)
            in (await repository.balances(at: at)).entries) {
          if (value != 0) out['$day ${account.key} $currency'] = value;
        }
      }
      return out;
    }

    test('after a run of fixes, a journal built again from nothing has '
        'the balances the incremental one reached', () async {
      final expenses = await (db.select(
        db.categories,
      )..where((c) => c.type.equalsValue(CategoryType.expense))).get();
      await transactions.add(
        tx(mpesa, eat(2026, 11, 2), kes(100), balance: kes(900)),
      );
      final wrong = await transactions.add(tx(kcb, eat(2026, 11, 3), kes(250)));
      await transactions.add(
        tx(mpesa, eat(2026, 11, 4), kes(100), balance: kes(550)),
      );
      await log.check();
      await balances.moveToAccount(wrong, mpesa);
      await log.check();
      final (sent, got) = await transfer(kes(2030), kes(2000), day: 5);
      await transactions.match(sent, got);
      await log.check();
      final (sent2, got2) = await transfer(kes(700), kes(700), day: 6);
      await transactions.match(sent2, got2);
      await log.check();
      await transactions.unmatch(sent2);
      await log.check();
      final named = await transactions.add(
        tx(kcb, eat(2026, 11, 7, 10), kes(900), kind: TransactionKind.bank),
      );
      await transactions.setTransferAccount(named, cash);
      await log.check();
      final set = await balances.setBalance(
        kcb,
        statedMinor: kes(15000),
        differenceMinor: -kes(120),
        at: eat(2026, 11, 10),
        currency: 'KES',
      );
      await log.check();
      await balances.undoCorrection(set);
      await log.check();
      await balances.setBalance(
        mpesa,
        statedMinor: -kes(200),
        differenceMinor: -kes(2750),
        at: eat(2026, 11, 12),
        currency: 'KES',
      );
      await log.check();
      final paid = await transactions.add(
        tx(mpesa, eat(2026, 11, 14), kes(80), category: expenses[0].id),
      );
      await (db.update(db.transactions)..where((t) => t.id.equals(paid))).write(
        TransactionsCompanion(categoryOverrideId: Value(expenses[1].id)),
      );
      await settled();

      // The same records in a new database, posted in one go.
      final fresh = openTestDatabase();
      await fresh.delete(fresh.categories).go();
      // Rows point at each other, in any order.
      await fresh.customStatement('PRAGMA foreign_keys = OFF');
      for (final TableInfo<Table, Object?> table in [
        db.categories,
        db.accounts,
        db.transactions,
        db.declinedTransfers,
      ]) {
        final rows = await db
            .customSelect(
              'SELECT * FROM ${table.actualTableName} ORDER BY rowid',
              readsFrom: {table},
            )
            .get();
        for (final row in rows) {
          final columns = row.data.keys.toList();
          await fresh.customStatement(
            'INSERT INTO ${table.actualTableName} (${columns.join(', ')}) '
            'VALUES (${List.filled(columns.length, '?').join(', ')})',
            [for (final c in columns) row.data[c]],
          );
        }
      }
      await fresh.customStatement('PRAGMA foreign_keys = ON');
      final rebuilt = JournalRepository(fresh, clock: () => monthEnd);
      await rebuilt.rebuild();
      expect(await rebuilt.unbalanced(), isEmpty);
      expect(await everyBalance(fresh), await everyBalance(db));
      // The incremental journal kept its history; the new one has none.
      expect(
        (await db.select(db.journalEntries).get()).where(
          (e) => e.reverses != null,
        ),
        isNotEmpty,
      );
      expect(
        (await fresh.select(fresh.journalEntries).get()).where(
          (e) => e.reverses != null,
        ),
        isEmpty,
      );
    });

    test("clearing a space's data starts its journal again from the "
        'accounts it keeps', () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          personalDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => monthEnd),
        ],
      );
      addTearDown(container.dispose);
      await transactions.add(tx(cash, eat(2026, 11, 2), kes(100)));
      await log.check();
      expect(await of(BookAccount.money(cash)), kes(400));

      await container
          .read(spaceManagerProvider)
          .clear(Space.personal, keep: false);
      // The records are gone, and the journal with them.
      expect(await db.select(db.transactions).get(), isEmpty);
      expect(await db.select(db.journalEntries).get(), isEmpty);
      // Each account reads what it was opened with.
      expect(await of(BookAccount.money(cash)), kes(500));
      expect(await of(BookAccount.money(kcb)), kes(20000));
      expect(await of(BookAccount.money(mpesa)), kes(1000));
      expect(await journal.unbalanced(), isEmpty);
      expect((await journal.rebuild()).changed, isFalse);
    });

    test('clearing a range of days reverses what it removes', () async {
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          personalDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => monthEnd),
        ],
      );
      addTearDown(container.dispose);
      final kept = await transactions.add(tx(cash, eat(2026, 11, 2), kes(100)));
      final (sent, got) = await transfer(kes(2030), kes(2000), day: 5);
      await transactions.match(sent, got);
      await transactions.add(tx(mpesa, eat(2026, 11, 6), kes(50)));
      await log.check();

      await container
          .read(spaceManagerProvider)
          .clear(
            Space.personal,
            keep: false,
            from: eat(2026, 11, 5, 10, 1),
            to: eat(2026, 11, 7, 0),
          );
      await settled();
      // M-Pesa's side of the transfer and the payment went; KCB's stays,
      // on its own.
      expect(await of(BookAccount.money(mpesa)), kes(1000));
      expect(await of(BookAccount.money(kcb)), kes(20000 - 2030));
      expect(await of(BookAccount.moneyInTransit), 0);
      expect(await of(BookAccount.fees), 0);
      expect(await entriesFor(kept), hasLength(1));
      expect(await entriesFor(got), hasLength(2));
    });
  });
}
