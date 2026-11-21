// Currencies stage 2, wired in: own transfers across currencies pair as
// messages arrive and once over past history, the journal posts their
// exchange, and the figures count what the exchange cost with fees.
//
// Synthetic data only: invented accounts, numbers, amounts and rates.
// "Today" is Saturday 21 November 2026; the day's rate is 1 USD = 129.20
// KES.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/rate_history_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/books/books.dart';
import 'package:pesaclarity/src/domain/books/business_report.dart';
import 'package:pesaclarity/src/domain/insights/leakage.dart';
import 'package:pesaclarity/src/domain/ledger/activity_feed.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';

import '../domain/fixtures.dart';
import '../helpers/balance_oracle.dart';
import '../helpers/journal_history.dart';
import '../helpers/test_app.dart';

/// Dollars and cents to minor units.
int usd(int dollars, [int cents = 0]) => dollars * 100 + cents;

void main() {
  late AppDatabase db;
  late JournalRepository journal;
  late DriftTransactionsRepository transactions;
  late JournalLog log;
  late int shillings; // KCB ···4321, KES
  late int dollars; // KCB ···8765, USD
  late int equity; // Equity Bank ···0002, USD
  late int mpesa;
  final today = CalendarDate(2026, 11, 21);
  final monthEnd = eat(2026, 12, 1, 0);

  Future<int> account(
    String name,
    String currency,
    int balance, {
    String? institution,
    String? reference,
    AccountType type = AccountType.bank,
  }) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: name,
          type: type,
          currency: Value(currency),
          openingBalanceMinor: Value(balance),
          openingDate: eat(2026, 11, 1, 0),
          institutionId: Value(institution),
          reference: Value(reference),
        ),
      );

  /// Keeps [usdInShillings] as the rate of [day] of November 2026.
  Future<void> keepRate(int day, double usdInShillings) =>
      DriftRateHistoryRepository(db).keep(
        CalendarDate(2026, 11, day),
        ExchangeRates(
          base: 'KES',
          rates: {'KES': 1, 'USD': 1 / usdInShillings},
          fetchedAt: eat(2026, 11, day, 7),
        ),
      );

  setUp(() async {
    db = openTestDatabase();
    journal = JournalRepository(db, clock: () => monthEnd);
    transactions = DriftTransactionsRepository(db);
    log = JournalLog(db, journal);
    shillings = await account(
      'KCB ···4321',
      'KES',
      kes(50000),
      institution: 'kcb',
      reference: '1100****4321',
    );
    dollars = await account(
      'KCB ···8765',
      'USD',
      0,
      institution: 'kcb',
      reference: '1100****8765',
    );
    equity = await account(
      'Equity Bank ···0002',
      'USD',
      0,
      institution: 'equity',
      reference: '0170*****0002',
    );
    mpesa = await account(
      'M-Pesa',
      'KES',
      kes(8000),
      institution: 'mpesa',
      type: AccountType.mpesa,
    );
  });

  var n = 0;
  TransactionsCompanion tx(
    int accountId,
    DateTime at,
    int amount, {
    String currency = 'KES',
    bool inflow = false,
    TransactionKind kind = TransactionKind.bank,
    int fee = 0,
    int? balance,
    int? category,
  }) => TransactionsCompanion.insert(
    accountId: accountId,
    occurredAt: at,
    amountMinor: amount,
    currency: Value(currency),
    direction: inflow
        ? TransactionDirection.inflow
        : TransactionDirection.outflow,
    kind: Value(kind),
    feeMinor: Value(fee),
    source: TransactionSource.sms,
    dedupeKey: Value('k${n++}'),
    balanceAfterMinor: Value(balance),
    categoryOverrideId: Value(category),
  );

  /// The worked example's two messages, KES [out] at 10:00 and USD [into]
  /// at 10:02 on [day], as they arrive.
  Future<(int, int)> exchange({
    int out = 1305000,
    int into = 10000,
    int day = 21,
    int fee = 0,
    int? toAccount,
  }) async {
    await transactions.addNew([
      tx(shillings, eat(2026, 11, day, 10), out, fee: fee),
    ]);
    await transactions.addNew([
      tx(
        toAccount ?? dollars,
        eat(2026, 11, day, 10, 2),
        into,
        currency: 'USD',
        inflow: true,
      ),
    ]);
    final rows = await (db.select(
      db.transactions,
    )..orderBy([(t) => OrderingTerm.desc(t.id)])).get();
    return (rows[1].id, rows[0].id);
  }

  Future<TransactionRecord> row(int id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();

  Future<CurrencyConverter> converter() =>
      CurrencyController.storedConverter(db);

  /// The ledger as the app reads it: converted into the base.
  Future<List<LedgerEntry>> ledger() async => DriftTransactionsRepository(
    db,
    converter: await converter(),
  ).ledgerEntries(from: DateTime.utc(1970), to: DateTime.utc(9999));

  Future<int> stored(BookAccount a, String currency) async =>
      (await journal.balances())[(a, currency)] ?? 0;

  /// After a change: nothing stored was edited, every entry balances in
  /// each currency, a rebuild changes nothing, and money accounts are
  /// what the records add up to.
  Future<void> settled() async {
    await log.check();
    expect((await journal.rebuild()).changed, isFalse);
    expect(await reconcileWithOracle(db, at: monthEnd), isEmpty);
  }

  group('pairing', () {
    test('two accounts at one bank, two minutes apart and within 5% of the '
        "day's rate, pair by themselves as the messages arrive", () async {
      await keepRate(21, 129.2);
      final (out, into) = await exchange();
      expect((await row(out)).transferPairId, into);
      expect((await row(into)).transferPairId, out);
      // Nothing is written onto either side: the rate got is the ratio.
      expect((await row(into)).fxRateMicros, isNull);
      expect((await row(out)).fxRateMicros, isNull);
    });

    test('with no rate kept for the day nothing pairs by itself', () async {
      final (out, into) = await exchange();
      expect((await row(out)).transferPairId, isNull);
      expect((await row(into)).transferPairId, isNull);
    });

    test('a move the person named waits for money in USD at another bank, '
        'up to 3 days', () async {
      await keepRate(19, 129.2);
      final sent = await transactions.add(
        tx(shillings, eat(2026, 11, 19, 10), kes(6500)),
      );
      await transactions.setTransferAccount(sent, equity);
      await transactions.addNew([
        tx(
          equity,
          eat(2026, 11, 21, 9),
          usd(50),
          currency: 'USD',
          inflow: true,
        ),
      ]);
      expect((await row(sent)).transferPairId, isNotNull);
    });

    test(
      'two banks with nothing named are only offered, never paired',
      () async {
        await keepRate(21, 129.2);
        final (out, into) = await exchange(toAccount: equity);
        expect((await row(out)).transferPairId, isNull);
        final container = ProviderContainer(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
        );
        addTearDown(container.dispose);
        await container.read(currencyControllerProvider.future);
        final offered = await container.read(
          crossCurrencySuggestionsProvider((id: out, at: eat(2026, 11, 21, 10)))
              .future,
        );
        expect([for (final t in offered) t.inflow.id], [into]);
        expect(offered.single.rateGot, closeTo(1 / 130.5, 1e-9));
      },
    );

    test('a side the bank reverses later unmatches the pair, and it is '
        'never paired again', () async {
      await keepRate(21, 129.2);
      final (out, into) = await exchange();
      expect((await row(out)).transferPairId, into);
      await transactions.addNew([
        tx(
          shillings,
          eat(2026, 11, 21, 15),
          kes(13050),
          inflow: true,
          kind: TransactionKind.reversal,
        ),
      ]);
      expect((await row(out)).transferPairId, isNull);
      expect((await row(into)).transferPairId, isNull);
      expect(await transactions.declinedTransfers(), hasLength(1));
      await transactions.pairOwnTransfers();
      expect((await row(into)).transferPairId, isNull);
    });

    test('history pairs again once after the update that pairs across '
        'currencies (version 2)', () async {
      await keepRate(21, 129.2);
      // Stored before this update, straight into the table.
      final out = await db
          .into(db.transactions)
          .insert(tx(shillings, eat(2026, 11, 21, 10), kes(13050)));
      final into = await db
          .into(db.transactions)
          .insert(
            tx(
              dollars,
              eat(2026, 11, 21, 10, 2),
              usd(100),
              currency: 'USD',
              inflow: true,
            ),
          );
      await DriftAppSettingsRepository(db)
          .writeJson('ledger.ownTransfersPaired', {'version': 1});
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
      await container.read(pairHistoryOnceProvider.future);
      expect((await row(out)).transferPairId, into);
      expect(
        await DriftAppSettingsRepository(db)
            .readJson('ledger.ownTransfersPaired'),
        {'version': 2},
      );
    });
  });

  group('the journal', () {
    test('posts the exchange: transit clears in each currency, the cost is '
        'KES 130, and Currency exchange is zero in the base', () async {
      await keepRate(21, 129.2);
      final (out, into) = await exchange();
      await settled();
      expect(await stored(BookAccount.moneyInTransit, 'KES'), 0);
      expect(await stored(BookAccount.moneyInTransit, 'USD'), 0);
      expect(await stored(BookAccount.exchangeCost, 'KES'), kes(130));
      expect(await stored(BookAccount.currencyExchange, 'KES'), kes(12920));
      expect(await stored(BookAccount.currencyExchange, 'USD'), -usd(100));
      final inBase = await journal.read(converter: await converter());
      expect(
        inBase.balanceOf(BookAccount.currencyExchange, currency: 'KES'),
        0,
      );
      expect(inBase.balanceOf(BookAccount.moneyInTransit, currency: 'KES'), 0);
      expect(
        inBase.balanceOf(BookAccount.exchangeCost, currency: 'KES'),
        kes(130),
      );
      final exchanges = await (db.select(
        db.journalEntries,
      )..where((e) => e.sourceKind.equalsValue(JournalSource.exchange))).get();
      expect({for (final e in exchanges) e.sourceId}, {out, into});
    });

    test(
      'a rate kept later reposts the cost; nothing stored is edited',
      () async {
        final (out, into) = await exchange();
        await transactions.match(out, into);
        await settled();
        // No rate for the day: the cost is not known.
        expect(await stored(BookAccount.exchangeCost, 'KES'), 0);
        expect(await stored(BookAccount.currencyExchange, 'KES'), kes(13050));
        await keepRate(21, 129.2);
        await settled();
        expect(await stored(BookAccount.exchangeCost, 'KES'), kes(130));
        expect(await stored(BookAccount.moneyInTransit, 'KES'), 0);
        // The same rate again changes nothing.
        expect((await journal.sync()).changed, isFalse);
      },
    );

    test('unmatching reverses the exchange; each side counts as it reads '
        'alone', () async {
      await keepRate(21, 129.2);
      final (out, _) = await exchange();
      await log.check();
      await transactions.unmatch(out);
      await settled();
      expect(await stored(BookAccount.exchangeCost, 'KES'), 0);
      expect(await stored(BookAccount.currencyExchange, 'KES'), 0);
      expect(await stored(BookAccount.currencyExchange, 'USD'), 0);
      expect(await stored(BookAccount.moneyInTransit, 'KES'), 0);
      expect(await stored(BookAccount.moneyInTransit, 'USD'), 0);
      expect(
        await stored(BookAccount.uncategorisedSpending, 'KES'),
        kes(13050),
      );
    });

    test(
      'a fresh database with the same records posts the same exchange',
      () async {
        await keepRate(21, 129.2);
        await exchange(fee: kes(50));
        await settled();
        final again = JournalRepository(db, clock: () => monthEnd);
        expect((await again.rebuild()).changed, isFalse);
        expect(await stored(BookAccount.fees, 'KES'), kes(50));
        expect(await stored(BookAccount.exchangeCost, 'KES'), kes(130));
      },
    );
  });

  group('figures, as section 4 of the plan', () {
    late int food;
    late int salary;

    setUp(() async {
      food =
          (await (db.select(
                db.categories,
              )..where((c) => c.type.equalsValue(CategoryType.expense))).get())
              .first
              .id;
      salary = (await (db.select(
        db.categories,
      )..where((c) => c.type.equalsValue(CategoryType.income))).get()).first.id;
      // The week so far: KES 7,820 out, KES 2,500 in.
      await transactions.addNew([
        tx(
          mpesa,
          eat(2026, 11, 16),
          kes(6080),
          kind: TransactionKind.till,
          category: food,
        ),
        tx(
          mpesa,
          eat(2026, 11, 17),
          kes(2500),
          inflow: true,
          kind: TransactionKind.received,
          category: salary,
        ),
        tx(
          mpesa,
          eat(2026, 11, 21, 8),
          kes(1440),
          kind: TransactionKind.till,
          category: food,
        ),
        tx(
          mpesa,
          eat(2026, 11, 21, 9),
          kes(300),
          kind: TransactionKind.till,
          category: food,
        ),
      ]);
      await keepRate(16, 129.2);
    });

    Future<int> onHand() async {
      final c = await converter();
      final accounts = await DriftAccountsRepository(
        db,
        converter: c,
      ).openings();
      return (await journal.read(
        converter: c,
      )).totalHeldAt(accounts, at: monthEnd, where: (a) => a.currency == 'KES');
    }

    test('Out this week goes up by the cost only, In does not move, and '
        'On hand goes down by the cost only', () async {
      final outBefore = weekInOut(await ledger(), today: today);
      final heldBefore = await onHand();
      expect(outBefore.outMinor, kes(7820));
      expect(outBefore.inMinor, kes(2500));

      await keepRate(21, 129.2);
      final (_, into) = await exchange();
      final entries = await ledger();
      final after = weekInOut(entries, today: today);
      expect(after.outMinor, kes(7950));
      expect(after.inMinor, kes(2500));
      expect(await onHand(), heldBefore - kes(130));
      expect(
        entries.singleWhere((e) => e.id == into).exchangeCostMinor,
        kes(130),
      );
    });

    test('the cost counts with fees in totals, Leakage and the business '
        "books' Exchange cost; a gain lowers fees", () async {
      await keepRate(21, 129.2);
      await exchange();
      // KES 12,900 bought USD 100.00 on another day: a gain of KES 20.
      await exchange(out: kes(12900), day: 22);
      final entries = await ledger();
      final from = eat(2026, 11, 21, 0);
      final to = eat(2026, 11, 23, 0);
      final totals = LedgerTotals.of(entries, from: from, to: to);
      expect(totals.feesMinor, kes(130 - 20));
      expect(totals.ownTransferMinor, kes(13050 + 12900));
      expect(totals.incomeMinor, 0);
      final leaks = LeakageBreakdown.of(entries, from: from, to: to);
      expect(leaks.feesMinor, kes(110));
      final books = Books.of(
        entries,
        accounts: await DriftAccountsRepository(
          db,
          converter: await converter(),
        ).openings(),
        categories: const {},
      );
      expect(books.unbalanced, isEmpty);
      expect(
        books.balanceOf(BookAccount.exchangeCost, currency: 'KES'),
        kes(110),
      );
      expect(books.balanceOf(BookAccount.ownTransfers, currency: 'KES'), 0);
      expect(
        bookAccountName(BookAccount.exchangeCost, const {}),
        'Exchange cost',
      );
    });

    test('only an approximate rate: the cost is not known', () async {
      // The oldest kept rate is a day after the move.
      await db.delete(db.rateSnapshots).go();
      await keepRate(22, 129.2);
      final (out, into) = await exchange();
      await transactions.match(out, into);
      final entries = await ledger();
      expect(
        entries.singleWhere((e) => e.id == into).exchangeCostMinor,
        isNull,
      );
      await log.check();
      expect(await stored(BookAccount.exchangeCost, 'KES'), 0);
    });
  });
}
