// The replay month for currencies stage 2: a synthetic November with a KES
// to USD move at one bank, a move the person named to another bank that
// arrives two days later, one into a currency with no rate kept (matched
// by hand), and one whose shilling side the bank reversed. Messages arrive
// one by one, as they would on the phone, and pair as they come. Every
// account must match the balances its messages reported, and On hand must
// be the sum the person would get by hand.
//
// Synthetic data only: invented accounts, numbers, amounts and rates.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/rate_history_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/ledger/activity_feed.dart';
import 'package:pesaclarity/src/domain/ledger/activity_lines.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';

import '../domain/fixtures.dart';
import '../helpers/balance_oracle.dart';
import '../helpers/journal_history.dart';
import '../helpers/test_app.dart';

int usd(int dollars, [int cents = 0]) => dollars * 100 + cents;

void main() {
  test('a month of moves across currencies: every account matches its '
      'reported balances, transit clears in every currency, and On hand is '
      'the sum by hand', () async {
    final db = openTestDatabase();
    final monthEnd = eat(2026, 12, 1, 0);
    final journal = JournalRepository(db, clock: () => monthEnd);
    final log = JournalLog(db, journal);
    final transactions = DriftTransactionsRepository(db);

    Future<int> account(
      String name,
      String currency,
      int balance, {
      required String institution,
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
    final shillings = await account(
      'KCB ···4321',
      'KES',
      kes(50000),
      institution: 'kcb',
      reference: '1100****4321',
    );
    final dollars = await account(
      'KCB ···8765',
      'USD',
      0,
      institution: 'kcb',
      reference: '1100****8765',
    );
    final euros = await account(
      'KCB ···5544',
      'EUR',
      0,
      institution: 'kcb',
      reference: '1100****5544',
    );
    final equity = await account(
      'Equity Bank ···0002',
      'USD',
      0,
      institution: 'equity',
      reference: '0170*****0002',
    );
    final mpesa = await account(
      'M-Pesa',
      'KES',
      kes(8000),
      institution: 'mpesa',
      type: AccountType.mpesa,
    );

    // Rates kept on three days; none for EUR at all.
    for (final (day, usdInShillings) in [
      (1, 128.5),
      (10, 129.0),
      (19, 128.0),
    ]) {
      await DriftRateHistoryRepository(db).keep(
        CalendarDate(2026, 11, day),
        ExchangeRates(
          base: 'KES',
          rates: {'KES': 1, 'USD': 1 / usdInShillings},
          fetchedAt: eat(2026, 11, day, 7),
        ),
      );
    }

    var n = 0;
    Future<int> arrives(
      int accountId,
      DateTime at,
      int amount, {
      required int balance,
      String currency = 'KES',
      bool inflow = false,
      TransactionKind kind = TransactionKind.bank,
    }) async {
      await transactions.addNew([
        TransactionsCompanion.insert(
          accountId: accountId,
          occurredAt: at,
          amountMinor: amount,
          currency: Value(currency),
          direction: inflow
              ? TransactionDirection.inflow
              : TransactionDirection.outflow,
          kind: Value(kind),
          source: TransactionSource.sms,
          dedupeKey: Value('m${n++}'),
          balanceAfterMinor: Value(balance),
        ),
      ]);
      await log.check();
      return (await (db.select(db.transactions)
                ..orderBy([(t) => OrderingTerm.desc(t.id)])
                ..limit(1))
              .getSingle())
          .id;
    }

    Future<int?> pairOf(int id) async => (await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(id))).getSingle()).transferPairId;

    await arrives(
      mpesa,
      eat(2026, 11, 3, 9),
      kes(1440),
      kind: TransactionKind.till,
      balance: kes(6560),
    );

    // 10 Nov: KES to USD at one bank, two minutes apart: pairs by itself.
    final out1 = await arrives(
      shillings,
      eat(2026, 11, 10, 10),
      kes(13050),
      balance: kes(36950),
    );
    final in1 = await arrives(
      dollars,
      eat(2026, 11, 10, 10, 2),
      usd(100),
      currency: 'USD',
      inflow: true,
      balance: usd(100),
    );
    expect(await pairOf(out1), in1);

    // 12 Nov: KES 6,500 the person said went to their Equity dollar
    // account; the dollars arrive two days later and pair by the name.
    final out2 = await arrives(
      shillings,
      eat(2026, 11, 12, 10),
      kes(6500),
      balance: kes(30450),
    );
    await transactions.setTransferAccount(out2, equity);
    await log.check();
    expect(
      await journal.balances(),
      containsPair((BookAccount.moneyInTransit, 'KES'), kes(6500)),
    );
    final in2 = await arrives(
      equity,
      eat(2026, 11, 14, 11),
      usd(50),
      currency: 'USD',
      inflow: true,
      balance: usd(50),
    );
    expect(await pairOf(out2), in2);

    // 15 Nov: into euros, with no rate kept for EUR: never by itself, so
    // the person matches it by hand.
    final out3 = await arrives(
      shillings,
      eat(2026, 11, 15, 10),
      kes(14000),
      balance: kes(16450),
    );
    final in3 = await arrives(
      euros,
      eat(2026, 11, 15, 10, 5),
      10000,
      currency: 'EUR',
      inflow: true,
      balance: 10000,
    );
    expect(await pairOf(out3), isNull);
    await transactions.match(out3, in3);
    await log.check();

    // 19 Nov: a move that pairs, then the bank reverses its shilling side:
    // the pair is unmatched and both count as they were.
    final out4 = await arrives(
      shillings,
      eat(2026, 11, 19, 10),
      kes(12800),
      balance: kes(3650),
    );
    final in4 = await arrives(
      dollars,
      eat(2026, 11, 19, 10, 1),
      usd(100),
      currency: 'USD',
      inflow: true,
      balance: usd(200),
    );
    expect(await pairOf(out4), in4);
    await arrives(
      shillings,
      eat(2026, 11, 19, 16),
      kes(12800),
      inflow: true,
      kind: TransactionKind.reversal,
      balance: kes(16450),
    );
    expect(await pairOf(out4), isNull);
    expect(await pairOf(in4), isNull);

    // Nothing stored was edited; a rebuild changes nothing.
    await log.check();
    expect((await journal.rebuild()).changed, isFalse);
    expect(await journal.unbalanced(), isEmpty);

    // Every account matches the balances its messages reported.
    expect(await journal.openGaps(), isEmpty);
    expect(await reconcileWithOracle(db, at: monthEnd), isEmpty);
    final stored = await journal.balances();
    int held(BookAccount a, String currency) => stored[(a, currency)] ?? 0;
    expect(held(BookAccount.money(shillings), 'KES'), kes(16450));
    expect(held(BookAccount.money(dollars), 'USD'), usd(200));
    expect(held(BookAccount.money(equity), 'USD'), usd(50));
    expect(held(BookAccount.money(euros), 'EUR'), 10000);
    expect(held(BookAccount.money(mpesa), 'KES'), kes(6560));

    // Money in transit is zero in every currency.
    for (final currency in ['KES', 'USD', 'EUR']) {
      expect(held(BookAccount.moneyInTransit, currency), 0, reason: currency);
    }
    // The exchange cost: 13,050 less 100.00 at 129.00 on the 10th, and
    // 6,500 less 50.00 at 129.00 (the 10th's, the closest earlier day) on
    // the 14th. The euro move's is not known.
    expect(held(BookAccount.exchangeCost, 'KES'), kes(150 + 50));
    expect(
      held(BookAccount.currencyExchange, 'KES'),
      kes(12900 + 6450 + 14000),
    );
    expect(held(BookAccount.currencyExchange, 'USD'), -usd(150));
    expect(held(BookAccount.currencyExchange, 'EUR'), -10000);

    // On hand, by hand: each account in the base at the rate of each
    // amount's day; the euros have no rate, so they are not in it yet.
    final converter = await CurrencyController.storedConverter(db);
    final openings = await DriftAccountsRepository(
      db,
      converter: converter,
    ).openings();
    final inBase = await journal.read(converter: converter);
    final byHand =
        kes(16450) + // KCB ···4321
        kes(6560) + // M-Pesa
        kes(100 * 129) + // KCB ···8765, 10 Nov
        kes(100 * 128) + // KCB ···8765, 19 Nov
        kes(50 * 129); // Equity Bank ···0002, 14 Nov
    expect(
      inBase.totalHeldAt(
        openings,
        at: monthEnd,
        where: (a) => a.currency == 'KES',
      ),
      byHand,
    );
    expect(inBase.balanceOf(BookAccount.moneyInTransit, currency: 'KES'), 0);
    // Zero in the base at the day's rates, but for the shillings sold for
    // euros: the euros have no rate, so they stay in EUR.
    expect(
      inBase.balanceOf(BookAccount.currencyExchange, currency: 'KES'),
      kes(14000),
    );
    expect(
      inBase.balanceOf(BookAccount.currencyExchange, currency: 'EUR'),
      -10000,
    );

    // The month's figures: the cost counts with fees; the moves are never
    // spending, and the reversal cancels the side it undid.
    final entries = await DriftTransactionsRepository(
      db,
      converter: converter,
    ).ledgerEntries(from: DateTime.utc(1970), to: DateTime.utc(9999));
    final totals = LedgerTotals.of(
      entries,
      from: eat(2026, 11, 1, 0),
      to: monthEnd,
    );
    expect(totals.feesMinor, kes(200));
    expect(totals.spendingMinor, kes(1440));

    // Activity shows each matched move once.
    final transfers = [
      for (final day in buildActivityFeed(entries, all: entries))
        for (final line in day.lines)
          if (line is OwnTransferLine && line.inflow != null) line,
    ];
    expect({for (final t in transfers) t.outflow!.id}, {out1, out2, out3});
  });
}
