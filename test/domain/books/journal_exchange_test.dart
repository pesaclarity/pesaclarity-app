// Currencies stage 2, the journal: an own transfer across currencies posts
// each side as before, then one exchange entry per currency, dated when the
// money arrived. Every entry sums to zero in its currency, Money in transit
// clears in each, and what the exchange cost against the day's rate goes
// to Exchange cost.
//
// Synthetic data only: invented accounts, amounts and rates. "Today" is
// Saturday 21 November 2026; the day's rate is 1 USD = 129.20 KES.
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/books/books.dart';
import 'package:pesaclarity/src/domain/books/journal.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/cross_currency_transfers.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';

import '../fixtures.dart';

const shillings = 1; // KCB ···4321, KES
const dollars = 2; // KCB ···8765, USD

final accounts = [
  AccountOpening(
    id: shillings,
    type: AccountType.bank,
    openingBalanceMinor: kes(50000),
    openingDate: eat(2026, 11, 1, 0),
  ),
  AccountOpening(
    id: dollars,
    type: AccountType.bank,
    currency: 'USD',
    openingBalanceMinor: 0,
    openingDate: eat(2026, 11, 1, 0),
  ),
];

/// Rates from what one unit of each currency is worth in shillings, by
/// day of November (the 21st when a day is not given).
DayRate ratesBy(Map<int, double> usdByDay, {bool approximate = false}) =>
    (from, to, at) {
      final day = at.add(const Duration(hours: 3)).day;
      final usd = usdByDay[day] ?? usdByDay[21];
      if (usd == null) return null;
      final inShillings = {'KES': 1.0, 'USD': usd};
      final a = inShillings[from];
      final b = inShillings[to];
      return a == null || b == null
          ? null
          : DayRateQuote(a / b, approximate: approximate);
    };

final dayRates = ratesBy({21: 129.2});

/// Dollars and cents to minor units.
int usd(int dollars, [int cents = 0]) => dollars * 100 + cents;

LedgerEntry side(
  int id,
  int amount, {
  required int accountId,
  required String currency,
  required bool inflow,
  DateTime? at,
  int? pairedWith,
  int? namedAccount,
  int fee = 0,
}) => LedgerEntry(
  id: id,
  accountId: accountId,
  occurredAt: at ?? eat(2026, 11, 21, 10, inflow ? 2 : 0),
  amountMinor: amount,
  direction: inflow
      ? TransactionDirection.inflow
      : TransactionDirection.outflow,
  kind: TransactionKind.bank,
  currency: currency,
  feeMinor: fee,
  transferPairId: pairedWith,
  transferAccountId: namedAccount,
);

/// KES [out] out of the shilling account and USD [into] into the dollar
/// account, paired.
List<LedgerEntry> kesToUsd(
  int out,
  int into, {
  int fee = 0,
  DateTime? outAt,
  DateTime? inAt,
}) => [
  side(
    1,
    out,
    accountId: shillings,
    currency: 'KES',
    inflow: false,
    at: outAt,
    pairedWith: 2,
    fee: fee,
  ),
  side(
    2,
    into,
    accountId: dollars,
    currency: 'USD',
    inflow: true,
    at: inAt,
    pairedWith: 1,
  ),
];

List<JournalEntry> post(List<LedgerEntry> history, {DayRate? rateOn}) =>
    postJournal(
      accounts: accounts,
      history: history,
      categories: const {},
      rateOn: rateOn,
    );

JournalEntry entryOf(
  List<JournalEntry> journal,
  JournalSource source,
  int id,
) => journal.singleWhere((e) => e.source == source && e.sourceId == id);

Map<BookAccount, int> lines(JournalEntry e) => {
  for (final l in e.lines) l.account: l.amountMinor,
};

int left(List<JournalEntry> journal, BookAccount a, String currency) =>
    journalBalance(journal, a, currency: currency);

void main() {
  group('the worked example: KES 13,050 out, USD 100.00 in', () {
    final journal = post(kesToUsd(kes(13050), usd(100)), rateOn: dayRates);

    test('each side posts as before, through Money in transit', () {
      expect(lines(entryOf(journal, JournalSource.transaction, 1)), {
        const BookAccount.money(shillings): -kes(13050),
        BookAccount.moneyInTransit: kes(13050),
      });
      expect(lines(entryOf(journal, JournalSource.transaction, 2)), {
        const BookAccount.money(dollars): usd(100),
        BookAccount.moneyInTransit: -usd(100),
      });
    });

    test('the shilling exchange: Currency exchange 12,920 and Exchange '
        'cost 130 against transit 13,050, dated when the money arrived', () {
      final kesSide = entryOf(journal, JournalSource.exchange, 1);
      expect(kesSide.currency, 'KES');
      expect(kesSide.at, eat(2026, 11, 21, 10, 2));
      expect(kesSide.accountId, shillings);
      expect(lines(kesSide), {
        BookAccount.currencyExchange: kes(12920),
        BookAccount.exchangeCost: kes(130),
        BookAccount.moneyInTransit: -kes(13050),
      });
    });

    test('the dollar exchange: transit 100.00 against Currency exchange', () {
      final usdSide = entryOf(journal, JournalSource.exchange, 2);
      expect(usdSide.currency, 'USD');
      expect(usdSide.at, eat(2026, 11, 21, 10, 2));
      expect(usdSide.accountId, dollars);
      expect(lines(usdSide), {
        BookAccount.moneyInTransit: usd(100),
        BookAccount.currencyExchange: -usd(100),
      });
    });

    test('every entry sums to zero in its currency; transit is zero in '
        'both; Currency exchange is zero in the base at the day\'s rate', () {
      expect(journal.where((e) => !e.isBalanced), isEmpty);
      expect(left(journal, BookAccount.moneyInTransit, 'KES'), 0);
      expect(left(journal, BookAccount.moneyInTransit, 'USD'), 0);
      final exchangeKes = left(journal, BookAccount.currencyExchange, 'KES');
      final exchangeUsd = left(journal, BookAccount.currencyExchange, 'USD');
      expect(exchangeKes, kes(12920));
      expect(exchangeUsd, -usd(100));
      expect(
        exchangeKes +
            convertMinor(exchangeUsd, from: 'USD', to: 'KES', rate: 129.2),
        0,
      );
      expect(left(journal, BookAccount.exchangeCost, 'KES'), kes(130));
      expect(
        left(journal, const BookAccount.money(shillings), 'KES'),
        kes(36950),
      );
      expect(left(journal, const BookAccount.money(dollars), 'USD'), usd(100));
      expect(left(journal, BookAccount.notYetSorted, 'KES'), 0);
      expect(left(journal, BookAccount.fees, 'KES'), 0);
    });
  });

  test('a fee the message printed posts as before, and the cost is worked '
      'out without it', () {
    final journal = post(
      kesToUsd(kes(13050), usd(100), fee: kes(50)),
      rateOn: dayRates,
    );
    expect(lines(entryOf(journal, JournalSource.transaction, 1)), {
      const BookAccount.money(shillings): -kes(13100),
      BookAccount.moneyInTransit: kes(13050),
      BookAccount.fees: kes(50),
    });
    expect(left(journal, BookAccount.exchangeCost, 'KES'), kes(130));
    expect(left(journal, BookAccount.fees, 'KES'), kes(50));
    expect(left(journal, BookAccount.moneyInTransit, 'KES'), 0);
  });

  test('USD 100.00 sold for KES 12,750: the cost is in the money out\'s '
      'currency, USD 1.32', () {
    final journal = post([
      side(
        1,
        usd(100),
        accountId: dollars,
        currency: 'USD',
        inflow: false,
        pairedWith: 2,
      ),
      side(
        2,
        kes(12750),
        accountId: shillings,
        currency: 'KES',
        inflow: true,
        pairedWith: 1,
      ),
    ], rateOn: dayRates);
    expect(lines(entryOf(journal, JournalSource.exchange, 1)), {
      BookAccount.currencyExchange: usd(98, 68),
      BookAccount.exchangeCost: usd(1, 32),
      BookAccount.moneyInTransit: -usd(100),
    });
    expect(lines(entryOf(journal, JournalSource.exchange, 2)), {
      BookAccount.moneyInTransit: kes(12750),
      BookAccount.currencyExchange: -kes(12750),
    });
    expect(journal.where((e) => !e.isBalanced), isEmpty);
    expect(left(journal, BookAccount.moneyInTransit, 'USD'), 0);
    expect(left(journal, BookAccount.moneyInTransit, 'KES'), 0);
  });

  test('more in than the day\'s rate gives: the cost is negative, a gain '
      'at the day\'s rate', () {
    // KES 12,900 bought USD 100.00: at 129.20 it would buy 99.85.
    final journal = post(kesToUsd(kes(12900), usd(100)), rateOn: dayRates);
    expect(left(journal, BookAccount.exchangeCost, 'KES'), -kes(20));
    expect(left(journal, BookAccount.currencyExchange, 'KES'), kes(12920));
    expect(left(journal, BookAccount.moneyInTransit, 'KES'), 0);
  });

  test('two days apart: the exchange is dated when the money arrived, and '
      'the cost uses that day\'s rate', () {
    final journal = post(
      kesToUsd(
        kes(13050),
        usd(100),
        outAt: eat(2026, 11, 19, 10),
        inAt: eat(2026, 11, 21, 9),
      ),
      rateOn: ratesBy({19: 128, 21: 129.2}),
    );
    final kesSide = entryOf(journal, JournalSource.exchange, 1);
    expect(kesSide.at, eat(2026, 11, 21, 9));
    expect(lines(kesSide)[BookAccount.exchangeCost], kes(130));
    // While the dollars are on their way, the shillings wait in transit.
    expect(
      journalBalance(
        journal,
        BookAccount.moneyInTransit,
        currency: 'KES',
        at: eat(2026, 11, 20),
      ),
      kes(13050),
    );
    expect(left(journal, BookAccount.moneyInTransit, 'KES'), 0);
    expect(left(journal, BookAccount.moneyInTransit, 'USD'), 0);
  });

  test('no rate for the day: the whole money out goes to Currency '
      'exchange, and nothing to Exchange cost', () {
    for (final rateOn in [
      null,
      ratesBy({}),
      ratesBy({21: 129.2}, approximate: true),
    ]) {
      final journal = post(kesToUsd(kes(13050), usd(100)), rateOn: rateOn);
      expect(lines(entryOf(journal, JournalSource.exchange, 1)), {
        BookAccount.currencyExchange: kes(13050),
        BookAccount.moneyInTransit: -kes(13050),
      });
      expect(left(journal, BookAccount.exchangeCost, 'KES'), 0);
      expect(left(journal, BookAccount.moneyInTransit, 'KES'), 0);
      expect(left(journal, BookAccount.moneyInTransit, 'USD'), 0);
      expect(journal.where((e) => !e.isBalanced), isEmpty);
    }
  });

  test('a side the person named waits in transit alone, with no exchange '
      'entry until its other side matches', () {
    final journal = post([
      side(
        1,
        kes(13050),
        accountId: shillings,
        currency: 'KES',
        inflow: false,
        namedAccount: dollars,
      ),
    ], rateOn: dayRates);
    expect(journal.where((e) => e.source == JournalSource.exchange), isEmpty);
    expect(left(journal, BookAccount.moneyInTransit, 'KES'), kes(13050));
  });

  test('one currency: no exchange entries', () {
    final journal = post([
      side(
        1,
        kes(2030),
        accountId: shillings,
        currency: 'KES',
        inflow: false,
        pairedWith: 2,
      ),
      side(
        2,
        kes(2000),
        accountId: 3,
        currency: 'KES',
        inflow: true,
        pairedWith: 1,
      ),
    ], rateOn: dayRates);
    expect(journal.where((e) => e.source == JournalSource.exchange), isEmpty);
  });

  test('posting one account at a time gives the same exchange entries, '
      'each with its own side', () {
    final history = kesToUsd(kes(13050), usd(100));
    final both = post(history, rateOn: dayRates);
    final kesOnly = postJournal(
      accounts: [accounts.first],
      history: [history.first],
      categories: const {},
      partners: {2: history.last},
      rateOn: dayRates,
    );
    final usdOnly = postJournal(
      accounts: [accounts.last],
      history: [history.last],
      categories: const {},
      partners: {1: history.first},
      rateOn: dayRates,
    );
    String shape(Iterable<JournalEntry> entries) => [
      for (final e in entries)
        if (e.source == JournalSource.exchange)
          '${e.sourceId} ${e.currency} ${lines(e)}',
    ].join('; ');
    expect(shape([...kesOnly, ...usdOnly]), shape(both));
  });
}
