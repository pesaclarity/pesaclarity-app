import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/cross_currency_transfers.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/own_transfers.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

// Synthetic data only: invented accounts, numbers, amounts and rates.
// "Today" is Saturday 21 November 2026.

const shillings = 11; // KCB ···4321, KES
const dollars = 12; // KCB ···8765, USD
const euros = 13; // KCB ···5544, EUR
const uganda = 14; // KCB ···0077, UGX
const mpesa = 15; // M-Pesa, KES
const otherBank = 16; // Equity Bank ···0002, USD
const byHand = 17; // A dollar account added by hand

const accounts = {
  shillings: TransferAccount(
    currency: 'KES',
    reference: '1100****4321',
    institutionId: 'kcb',
  ),
  dollars: TransferAccount(
    currency: 'USD',
    reference: '1100****8765',
    institutionId: 'kcb',
  ),
  euros: TransferAccount(
    currency: 'EUR',
    reference: '1100****5544',
    institutionId: 'kcb',
  ),
  uganda: TransferAccount(
    currency: 'UGX',
    reference: '2200****0077',
    institutionId: 'kcb',
  ),
  mpesa: TransferAccount(currency: 'KES', institutionId: 'mpesa'),
  otherBank: TransferAccount(
    currency: 'USD',
    reference: '0170*****0002',
    institutionId: 'equity',
  ),
  byHand: TransferAccount(currency: 'USD'),
};

/// Rates from what one unit of each currency is worth in shillings.
DayRate ratesFrom(
  Map<String, double> inShillings, {
  bool approximate = false,
}) => (from, to, at) {
  final a = inShillings[from];
  final b = inShillings[to];
  return a == null || b == null
      ? null
      : DayRateQuote(a / b, approximate: approximate);
};

/// The day's rates: 1 USD = 129.20 KES, 1 EUR = 140.00 KES and
/// 1 KES = 28.40 UGX.
final dayRates = ratesFrom({
  'KES': 1,
  'USD': 129.2,
  'EUR': 140,
  'UGX': 1 / 28.4,
});

DayRateQuote? noRates(String from, String to, DateTime at) => null;

/// Dollars and cents to minor units.
int usd(int dollars, [int cents = 0]) => dollars * 100 + cents;

LedgerEntry moneyOut(
  int id,
  int amount, {
  int accountId = shillings,
  String currency = 'KES',
  DateTime? at,
  int minute = 0,
  TransactionKind kind = TransactionKind.bank,
  int fee = 0,
  int? to,
  int? pairedWith,
  TransactionSource source = TransactionSource.sms,
  CategoryType? categoryType,
  PayeeIdentifierKind? counterpartyKind,
  String? counterpartyValue,
}) => LedgerEntry(
  id: id,
  accountId: accountId,
  occurredAt: at ?? eat(2026, 11, 21, 10, minute),
  amountMinor: amount,
  direction: TransactionDirection.outflow,
  kind: kind,
  currency: currency,
  feeMinor: fee,
  transferAccountId: to,
  transferPairId: pairedWith,
  source: source,
  categoryType: categoryType,
  counterpartyKind: counterpartyKind,
  counterpartyValue: counterpartyValue,
);

LedgerEntry moneyIn(
  int id,
  int amount, {
  int accountId = dollars,
  String currency = 'USD',
  DateTime? at,
  int minute = 2,
  TransactionKind kind = TransactionKind.bank,
  int? from,
  int? pairedWith,
  TransactionSource source = TransactionSource.sms,
  CategoryType? categoryType,
  PayeeIdentifierKind? counterpartyKind,
  String? counterpartyValue,
}) => LedgerEntry(
  id: id,
  accountId: accountId,
  occurredAt: at ?? eat(2026, 11, 21, 10, minute),
  amountMinor: amount,
  direction: TransactionDirection.inflow,
  kind: kind,
  currency: currency,
  transferAccountId: from,
  transferPairId: pairedWith,
  source: source,
  categoryType: categoryType,
  counterpartyKind: counterpartyKind,
  counterpartyValue: counterpartyValue,
);

List<CrossCurrencyTransfer> find(
  List<LedgerEntry> entries, {
  DayRate? rateOn,
  Set<TransferPair> declined = const {},
}) => findCrossCurrencyTransfers(
  entries,
  accounts: accounts,
  rateOn: rateOn ?? dayRates,
  declined: declined,
);

List<TransferPair> pairs(
  List<LedgerEntry> entries, {
  DayRate? rateOn,
  Set<TransferPair> declined = const {},
}) => [
  for (final t in find(entries, rateOn: rateOn, declined: declined)) t.pair,
];

List<CrossCurrencyTransfer> suggest(
  LedgerEntry entry,
  List<LedgerEntry> entries, {
  DayRate? rateOn,
  Set<TransferPair> declined = const {},
  int limit = 3,
}) => suggestCrossCurrencyPartners(
  entry,
  entries,
  accounts: accounts,
  rateOn: rateOn ?? dayRates,
  declined: declined,
  limit: limit,
);

void main() {
  group('a move between a shilling and a dollar account at one bank', () {
    // KES 13,050 out and USD 100.00 in: 1 USD = 130.50 KES, against the
    // day's 129.20.
    final out = moneyOut(1, kes(13050));
    final into = moneyIn(2, usd(100));

    test('is one transfer', () {
      final found = find([out, into]);
      expect(found, hasLength(1));
      final transfer = found.single;
      expect(transfer.pair, const TransferPair(1, 2));
      expect(transfer.tie, CrossCurrencyTie.sameInstitution);
      expect(transfer.fit, CrossCurrencyFit.atRate);
      expect(transfer.gap, const Duration(minutes: 2));
    });

    test('whichever message comes first', () {
      final early = moneyIn(2, usd(100), at: eat(2026, 11, 21, 9, 58));
      expect(pairs([early, out]), [const TransferPair(1, 2)]);
      expect(pairs([out, early]), [const TransferPair(1, 2)]);
    });

    test('keeps each amount in its own currency', () {
      final transfer = find([out, into]).single;
      expect((transfer.outMinor, transfer.outCurrency), (kes(13050), 'KES'));
      expect((transfer.inMinor, transfer.inCurrency), (usd(100), 'USD'));
      expect(transfer.partnerOf(out), same(into));
      expect(transfer.partnerOf(into), same(out));
    });

    test('the rate the person got is the ratio of the two amounts', () {
      final transfer = find([out, into]).single;
      // One shilling bought 0.00766 dollars: 1 USD = 130.50 KES.
      expect(1 / transfer.rateGot, closeTo(130.5, 1e-9));
    });

    test("says what it cost against the day's rate", () {
      final transfer = find([out, into]).single;
      // KES 13,050 at 129.20 is USD 101.01: USD 1.01 less came in, 1.0%.
      expect(transfer.expectedInMinor, usd(101, 1));
      expect(transfer.costMinor, usd(1, 1));
      expect(transfer.costBasisPoints, 100);
      // In shillings: 13,050 less USD 100.00 at 129.20, which is 12,920.
      expect(transfer.costIn('KES', dayRates), kes(130));
      // And the same seen from a dollar base.
      expect(transfer.costIn('USD', dayRates), usd(1, 1));
    });
  });

  group('either way round, and between any two currencies', () {
    test('dollars out and shillings in', () {
      // USD 100.00 sold for KES 12,750: 1 USD = 127.50 KES.
      final out = moneyOut(1, usd(100), accountId: dollars, currency: 'USD');
      final into = moneyIn(
        2,
        kes(12750),
        accountId: shillings,
        currency: 'KES',
      );
      final transfer = find([out, into]).single;
      expect(transfer.pair, const TransferPair(1, 2));
      expect(transfer.rateGot, closeTo(127.5, 1e-9));
      expect(transfer.expectedInMinor, kes(12920));
      expect(transfer.costIn('KES', dayRates), kes(170));
      expect(transfer.costBasisPoints, 132);
    });

    test('neither currency is the one the person counts in', () {
      // USD 100.00 at the day's rates is EUR 92.29; EUR 91.00 came in.
      final out = moneyOut(1, usd(100), accountId: dollars, currency: 'USD');
      final into = moneyIn(2, 9100, accountId: euros, currency: 'EUR');
      final transfer = find([out, into]).single;
      expect(transfer.expectedInMinor, 9229);
      expect(transfer.fit, CrossCurrencyFit.atRate);
      // In shillings: 12,920 out, 91.00 x 140 = 12,740 in.
      expect(transfer.costIn('KES', dayRates), kes(180));
    });

    test('a currency with no cents', () {
      // KES 10,000 at 28.40 is UGX 284,000; UGX 280,000 came in.
      final out = moneyOut(1, kes(10000));
      final into = moneyIn(2, 280000, accountId: uganda, currency: 'UGX');
      final transfer = find([out, into]).single;
      expect(transfer.expectedInMinor, 284000);
      expect(transfer.costMinor, 4000);
      expect(transfer.rateGot, closeTo(28, 1e-9));
    });

    test('across midnight', () {
      final out = moneyOut(1, kes(13050), at: eat(2026, 11, 20, 23, 55));
      final into = moneyIn(2, usd(100), at: eat(2026, 11, 21, 0, 10));
      expect(pairs([out, into]), [const TransferPair(1, 2)]);
    });

    test('entries read converted into the base keep their own amounts', () {
      // As Activity reads them: the dollar side shown in shillings.
      final into = LedgerEntry(
        id: 2,
        accountId: dollars,
        occurredAt: eat(2026, 11, 21, 10, 2),
        amountMinor: kes(12920),
        direction: TransactionDirection.inflow,
        kind: TransactionKind.bank,
        currency: 'KES',
        originalAmountMinor: usd(100),
        originalCurrency: 'USD',
      );
      final transfer = find([moneyOut(1, kes(13050)), into]).single;
      expect((transfer.inMinor, transfer.inCurrency), (usd(100), 'USD'));
    });
  });

  group('time window', () {
    test('30 minutes for two accounts at one bank', () {
      final out = moneyOut(1, kes(13050));
      expect(pairs([out, moneyIn(2, usd(100), minute: 30)]), hasLength(1));
      expect(pairs([out, moneyIn(2, usd(100), minute: 31)]), isEmpty);
    });

    test('a side the person named waits up to 3 days', () {
      final named = moneyOut(1, kes(13050), to: otherBank);
      LedgerEntry arrives(DateTime at) =>
          moneyIn(2, usd(100), accountId: otherBank, at: at);
      expect(pairs([named, arrives(eat(2026, 11, 24, 9))]), hasLength(1));
      expect(pairs([named, arrives(eat(2026, 11, 24, 10, 1))]), isEmpty);
      expect(
        find([named, arrives(eat(2026, 11, 23, 16))]).single.tie,
        CrossCurrencyTie.named,
      );
    });

    test('so does money in the person said came from another account', () {
      final out = moneyOut(1, kes(13050));
      final named = moneyIn(
        2,
        usd(100),
        accountId: otherBank,
        from: shillings,
        at: eat(2026, 11, 23),
      );
      expect(pairs([out, named]), [const TransferPair(1, 2)]);
    });
  });

  group("how far the rate may be from the day's", () {
    // KES 12,920 at the day's 129.20 is USD 100.00 exactly.
    final out = moneyOut(1, kes(12920));

    test('5% either way pairs two accounts at one bank', () {
      for (final cents in [usd(95), usd(100), usd(105)]) {
        final found = find([out, moneyIn(2, cents)]);
        expect(found.single.fit, CrossCurrencyFit.atRate, reason: '$cents');
      }
    });

    test('past 5% they do not pair by themselves', () {
      expect(pairs([out, moneyIn(2, usd(94, 99))]), isEmpty);
      expect(pairs([out, moneyIn(2, usd(105, 1))]), isEmpty);
    });

    test('up to 10% pairs when the person named the other account', () {
      final named = moneyOut(1, kes(12920), to: dollars);
      for (final cents in [usd(90), usd(94, 99), usd(105, 1), usd(110)]) {
        final found = find([named, moneyIn(2, cents)]);
        expect(found.single.fit, CrossCurrencyFit.loose, reason: '$cents');
      }
    });

    test('past 10% never, whoever named it', () {
      final named = moneyOut(1, kes(12920), to: dollars);
      expect(pairs([named, moneyIn(2, usd(89, 99))]), isEmpty);
      expect(pairs([named, moneyIn(2, usd(110, 1))]), isEmpty);
    });
  });

  group('what ties the two beyond time and rate', () {
    test('two institutions and nothing named: suggested, never paired', () {
      // Dollars from another bank land in M-Pesa at a likely rate.
      final out = moneyOut(1, usd(100), accountId: otherBank, currency: 'USD');
      final into = moneyIn(
        2,
        kes(12750),
        accountId: mpesa,
        currency: 'KES',
        kind: TransactionKind.received,
      );
      expect(pairs([out, into]), isEmpty);
      final offered = suggest(into, [out, into]).single;
      expect(offered.partnerOf(into), same(out));
      expect(offered.tie, isNull);
      expect(offered.fit, CrossCurrencyFit.atRate);
    });

    test('an account added by hand has no institution', () {
      final out = moneyOut(1, kes(13050));
      final into = moneyIn(2, usd(100), accountId: byHand);
      expect(pairs([out, into]), isEmpty);
      expect(suggest(out, [out, into]), hasLength(1));
    });

    test('money out that names the number of the account it went into', () {
      // A transfer to the person's own dollar account at another bank.
      final out = moneyOut(
        1,
        kes(13050),
        counterpartyKind: PayeeIdentifierKind.account,
        counterpartyValue: '0170*****0002',
      );
      final into = moneyIn(
        2,
        usd(100),
        accountId: otherBank,
        at: eat(2026, 11, 23, 9),
      );
      final transfer = find([out, into]).single;
      expect(transfer.tie, CrossCurrencyTie.accountNumber);
      expect(transfer.pair, const TransferPair(1, 2));
    });

    test('a paybill payment for the account number it went into', () {
      final out = moneyOut(
        1,
        kes(13050),
        accountId: mpesa,
        kind: TransactionKind.paybill,
        counterpartyKind: PayeeIdentifierKind.paybill,
        counterpartyValue: 'EXAMPLE BANK#01700000000002',
      );
      final into = moneyIn(2, usd(100), accountId: otherBank);
      expect(find([out, into]).single.tie, CrossCurrencyTie.accountNumber);
    });

    test('money in that names the account it came from', () {
      final out = moneyOut(1, kes(13050));
      final into = moneyIn(
        2,
        usd(100),
        accountId: otherBank,
        counterpartyKind: PayeeIdentifierKind.account,
        counterpartyValue: '1100****4321',
        at: eat(2026, 11, 22, 15),
      );
      expect(find([out, into]).single.tie, CrossCurrencyTie.accountNumber);
    });

    test('a number allows up to 10%, like a name', () {
      final out = moneyOut(
        1,
        kes(12920),
        counterpartyKind: PayeeIdentifierKind.account,
        counterpartyValue: '0170*****0002',
      );
      expect(
        find([out, moneyIn(2, usd(92), accountId: otherBank)]).single.fit,
        CrossCurrencyFit.loose,
      );
      expect(pairs([out, moneyIn(2, usd(89), accountId: otherBank)]), isEmpty);
    });

    test('money in that names another account never pairs', () {
      final out = moneyOut(1, kes(13050));
      final into = moneyIn(
        2,
        usd(100),
        counterpartyKind: PayeeIdentifierKind.account,
        counterpartyValue: '0550****9911',
      );
      expect(pairs([out, into]), isEmpty);
      expect(suggest(out, [out, into]), isEmpty);
    });

    test('money out that names another account never pairs', () {
      final out = moneyOut(
        1,
        kes(13050),
        counterpartyKind: PayeeIdentifierKind.account,
        counterpartyValue: '0550****9911',
      );
      expect(pairs([out, moneyIn(2, usd(100))]), isEmpty);
    });

    test('a side the person named for another account never pairs', () {
      final out = moneyOut(1, kes(13050), to: otherBank);
      final into = moneyIn(2, usd(100));
      expect(pairs([out, into]), isEmpty);
      expect(suggest(into, [out, into]), isEmpty);
    });
  });

  group('fees and charges', () {
    test('the fee a message prints is not part of the rate', () {
      // KES 13,050 moved and a KES 120 fee on top, printed by the message.
      final out = moneyOut(1, kes(13050), fee: kes(120));
      final transfer = find([out, moneyIn(2, usd(100))]).single;
      expect(1 / transfer.rateGot, closeTo(130.5, 1e-9));
      expect(transfer.costIn('KES', dayRates), kes(130));
    });

    test('a fee folded into the amount shows as a worse rate', () {
      // KES 13,050 for the dollars and a KES 300 charge in the same debit.
      final out = moneyOut(1, kes(13350));
      final transfer = find([out, moneyIn(2, usd(100))]).single;
      expect(1 / transfer.rateGot, closeTo(133.5, 1e-9));
      expect(transfer.costIn('KES', dayRates), kes(430));
      expect(transfer.fit, CrossCurrencyFit.atRate);
    });

    test('a small move with a flat fee is only suggested', () {
      // USD 10.00 for KES 1,300 plus a KES 100 charge: 8% over the day's.
      final out = moneyOut(1, kes(1400));
      final into = moneyIn(2, usd(10));
      expect(pairs([out, into]), isEmpty);
      expect(suggest(out, [out, into]).single.fit, CrossCurrencyFit.loose);
    });

    test('a charge that comes as its own message is never a side', () {
      final charge = moneyOut(1, kes(13050), kind: TransactionKind.charge);
      final into = moneyIn(2, usd(100));
      expect(pairs([charge, into]), isEmpty);
      expect(suggest(into, [charge, into]), isEmpty);
    });
  });

  group('two candidates', () {
    test('the closest in time pairs, and each entry is used once', () {
      final outA = moneyOut(1, kes(13050));
      final outB = moneyOut(2, kes(13050), minute: 10);
      final inA = moneyIn(3, usd(100), minute: 1);
      final inB = moneyIn(4, usd(100), minute: 11);
      final expected = {const TransferPair(1, 3), const TransferPair(2, 4)};
      expect(pairs([outA, outB, inA, inB]).toSet(), expected);
      expect(pairs([inB, inA, outB, outA]).toSet(), expected);
    });

    test('a number beats the closer in time', () {
      final out = moneyOut(
        1,
        kes(13050),
        counterpartyKind: PayeeIdentifierKind.account,
        counterpartyValue: '0170*****0002',
      );
      final near = moneyIn(2, usd(100), minute: 1);
      final numbered = moneyIn(3, usd(100), accountId: otherBank, minute: 25);
      // The dollar account at the same bank is numbered apart.
      expect(pairs([out, near, numbered]), [const TransferPair(1, 3)]);
    });

    test("the person's word beats the same bank", () {
      final out = moneyOut(1, kes(13050));
      final sameBank = moneyIn(2, usd(100), minute: 1);
      final named = moneyIn(
        3,
        usd(100),
        accountId: otherBank,
        from: shillings,
        minute: 20,
      );
      expect(pairs([out, sameBank, named]), [const TransferPair(1, 3)]);
    });

    test("at the same time, the one nearer the day's rate", () {
      final out = moneyOut(1, kes(12920));
      final near = moneyIn(2, usd(99));
      final far = moneyIn(3, usd(96));
      expect(pairs([out, far, near]), [const TransferPair(1, 2)]);
    });

    test('a rate fit within 5% beats a looser one for a named side', () {
      final out = moneyOut(1, kes(12920), to: dollars);
      final loose = moneyIn(2, usd(92), minute: 1);
      final close = moneyIn(3, usd(99), minute: 20);
      expect(pairs([out, loose, close]), [const TransferPair(1, 3)]);
    });

    test('two moves of different amounts each find their own side', () {
      final small = moneyOut(1, kes(13050));
      final large = moneyOut(2, kes(26100), minute: 1);
      final inLarge = moneyIn(3, usd(200), minute: 1);
      final inSmall = moneyIn(4, usd(100), minute: 3);
      expect(pairs([small, large, inLarge, inSmall]).toSet(), {
        const TransferPair(1, 4),
        const TransferPair(2, 3),
      });
    });
  });

  group('a partial match', () {
    test('money in for only part of the money out is not a pair', () {
      // KES 26,100 out, but only USD 100.00 in: 1 USD = 261 KES.
      final out = moneyOut(1, kes(26100));
      final into = moneyIn(2, usd(100));
      expect(pairs([out, into]), isEmpty);
      expect(suggest(out, [out, into]), isEmpty);
    });

    test('money that arrives in two parts is not paired', () {
      final out = moneyOut(1, kes(13050));
      final first = moneyIn(2, usd(60));
      final second = moneyIn(3, usd(40), minute: 3);
      expect(pairs([out, first, second]), isEmpty);
      expect(suggest(out, [out, first, second]), isEmpty);
    });

    test('the rate fits but the time does not: suggested', () {
      final out = moneyOut(1, kes(13050));
      final late = moneyIn(2, usd(100), at: eat(2026, 11, 22, 10));
      expect(pairs([out, late]), isEmpty);
      expect(suggest(out, [out, late]).single.fit, CrossCurrencyFit.atRate);
    });

    test('nothing is suggested more than 3 days away', () {
      final out = moneyOut(1, kes(13050));
      final late = moneyIn(2, usd(100), at: eat(2026, 11, 24, 10, 1));
      expect(suggest(out, [out, late]), isEmpty);
    });
  });

  group('a reversal', () {
    test('a reversal message is never a side', () {
      final out = moneyOut(1, kes(13050));
      final back = moneyIn(2, usd(100), kind: TransactionKind.reversal);
      expect(pairs([out, back]), isEmpty);
      expect(suggest(out, [out, back]), isEmpty);
    });

    test('money out the bank sent back is not a side', () {
      final out = moneyOut(1, kes(13050));
      final bounced = moneyIn(
        2,
        kes(13050),
        accountId: shillings,
        currency: 'KES',
        kind: TransactionKind.reversal,
        minute: 20,
      );
      // Dollars from elsewhere that happen to fit the rate.
      final into = moneyIn(3, usd(100), minute: 25);
      expect(reversedEntries([out, bounced, into]), {1});
      expect(pairs([out, bounced, into]), isEmpty);
      expect(suggest(into, [out, bounced, into]), isEmpty);
      expect(suggest(out, [out, bounced, into]), isEmpty);
    });

    test('money in the bank took back is not a side', () {
      final out = moneyOut(1, kes(13050));
      final into = moneyIn(2, usd(100));
      final takenBack = moneyOut(
        3,
        usd(100),
        accountId: dollars,
        currency: 'USD',
        kind: TransactionKind.reversal,
        minute: 30,
      );
      expect(pairs([out, into, takenBack]), isEmpty);
    });

    test('a reversal undoes one entry only, the latest before it', () {
      final first = moneyOut(1, kes(13050));
      final second = moneyOut(2, kes(13050), minute: 5);
      final bounced = moneyIn(
        3,
        kes(13050),
        accountId: shillings,
        currency: 'KES',
        kind: TransactionKind.reversal,
        minute: 10,
      );
      expect(reversedEntries([bounced, second, first]), {2});
      final into = moneyIn(4, usd(100), minute: 12);
      expect(pairs([first, second, bounced, into]), [const TransferPair(1, 4)]);
    });

    test('a reversal of another amount undoes nothing', () {
      final out = moneyOut(1, kes(13050));
      final refund = moneyIn(
        2,
        kes(500),
        accountId: shillings,
        currency: 'KES',
        kind: TransactionKind.reversal,
        minute: 10,
      );
      expect(reversedEntries([out, refund]), isEmpty);
      expect(pairs([out, refund, moneyIn(3, usd(100))]), [
        const TransferPair(1, 3),
      ]);
    });

    test('a move that is undone pairs as a second transfer back', () {
      final out = moneyOut(1, kes(13050));
      final into = moneyIn(2, usd(100));
      final dollarsBack = moneyOut(
        3,
        usd(100),
        accountId: dollars,
        currency: 'USD',
        minute: 40,
      );
      final shillingsBack = moneyIn(
        4,
        kes(13050),
        accountId: shillings,
        currency: 'KES',
        minute: 41,
      );
      final found = find([out, into, dollarsBack, shillingsBack]);
      expect(
        {for (final t in found) t.pair},
        {const TransferPair(1, 2), const TransferPair(3, 4)},
      );
      // What the first cost, the second gives back.
      final costs = [for (final t in found) t.costIn('KES', dayRates)!];
      expect(costs.reduce((a, b) => a + b), 0);
    });
  });

  group('a missing rate for that day', () {
    final out = moneyOut(1, kes(13050));
    final into = moneyIn(2, usd(100));

    test('nothing pairs by itself', () {
      expect(pairs([out, into], rateOn: noRates), isEmpty);
    });

    test('not even with a number or the person naming it', () {
      final named = moneyOut(1, kes(13050), to: dollars);
      expect(pairs([named, into], rateOn: noRates), isEmpty);
      final numbered = moneyOut(
        1,
        kes(13050),
        counterpartyKind: PayeeIdentifierKind.account,
        counterpartyValue: '1100****8765',
      );
      expect(pairs([numbered, into], rateOn: noRates), isEmpty);
    });

    test('the person can still match by hand', () {
      final offered = suggest(out, [out, into], rateOn: noRates).single;
      expect(offered.fit, CrossCurrencyFit.unchecked);
      expect(offered.dayRate, isNull);
      expect(offered.expectedInMinor, isNull);
      expect(offered.costMinor, isNull);
      expect(offered.costBasisPoints, isNull);
      expect(offered.costIn('KES', noRates), isNull);
      // The pair still has a rate of its own.
      expect(1 / offered.rateGot, closeTo(130.5, 1e-9));
    });

    test('a currency the rates do not list counts as no rate', () {
      final rates = ratesFrom({'KES': 1, 'EUR': 140});
      expect(pairs([out, into], rateOn: rates), isEmpty);
    });

    group('an approximate rate, kept on a later day', () {
      // The oldest rate the app has is today's 129.20; that day it was
      // nearer 150.
      final old = ratesFrom({'KES': 1, 'USD': 129.2}, approximate: true);

      test('pairs amounts that fit it', () {
        expect(pairs([out, into], rateOn: old), [const TransferPair(1, 2)]);
      });

      test('never rules a pair out of what the person is offered', () {
        final then = moneyOut(1, kes(15000));
        expect(pairs([then, into], rateOn: old), isEmpty);
        final offered = suggest(then, [then, into], rateOn: old).single;
        expect(offered.fit, CrossCurrencyFit.unchecked);
        // The cost against such a rate is not known.
        expect(offered.costIn('KES', old), isNull);
        // With a rate of that day, the same pair is not offered at all.
        expect(suggest(then, [then, into]), isEmpty);
      });
    });
  });

  group('never an own transfer across currencies', () {
    final out = moneyOut(1, kes(13050));
    final into = moneyIn(2, usd(100));

    test('two sides on one account', () {
      // A card payment in dollars on the shilling account and its debit.
      final card = moneyOut(2, usd(100), currency: 'USD', minute: 1);
      expect(pairs([out, card]), isEmpty);
    });

    test('a side not in the currency of its account', () {
      // Dollars paid by card from the shilling account are a payment, even
      // when shillings land elsewhere at a likely rate.
      final card = moneyOut(1, usd(100), currency: 'USD');
      final landed = moneyIn(
        2,
        kes(12900),
        accountId: mpesa,
        currency: 'KES',
        from: shillings,
      );
      expect(pairs([card, landed]), isEmpty);
      expect(suggest(card, [card, landed]), isEmpty);
      expect(suggest(landed, [card, landed]), isEmpty);
    });

    test('two amounts in the same currency', () {
      // Left to the same-currency rule.
      final sameCurrency = moneyIn(
        2,
        kes(13050),
        accountId: mpesa,
        currency: 'KES',
      );
      expect(pairs([out, sameCurrency]), isEmpty);
      expect(suggest(out, [out, sameCurrency]), isEmpty);
    });

    test('two amounts the same way', () {
      final alsoOut = moneyOut(
        2,
        usd(100),
        accountId: dollars,
        currency: 'USD',
      );
      expect(pairs([out, alsoOut]), isEmpty);
      expect(suggest(out, [out, alsoOut]), isEmpty);
    });

    test('an account the app does not know', () {
      final unknown = moneyIn(2, usd(100), accountId: 99);
      expect(pairs([out, unknown]), isEmpty);
    });

    test('till payments, withdrawals, airtime, Fuliza and loans', () {
      for (final kind in [
        TransactionKind.till,
        TransactionKind.withdrawal,
        TransactionKind.airtime,
        TransactionKind.fulizaRepayment,
        TransactionKind.loanRepayment,
        TransactionKind.roundUp,
      ]) {
        final other = moneyOut(1, kes(13050), kind: kind);
        expect(pairs([other, into]), isEmpty, reason: kind.name);
      }
      for (final kind in [
        TransactionKind.deposit,
        TransactionKind.fulizaDraw,
        TransactionKind.sent,
      ]) {
        final other = moneyIn(2, usd(100), kind: kind);
        expect(pairs([out, other]), isEmpty, reason: kind.name);
      }
    });

    test('a balance correction', () {
      final correction = moneyIn(2, usd(100), kind: TransactionKind.correction);
      expect(pairs([out, correction]), isEmpty);
      expect(suggest(correction, [out, correction]), isEmpty);
    });

    test('money in or out with a category that is not a transfer', () {
      final salary = moneyIn(2, usd(100), categoryType: CategoryType.income);
      expect(pairs([out, salary]), isEmpty);
      final rent = moneyOut(1, kes(13050), categoryType: CategoryType.expense);
      expect(pairs([rent, into]), isEmpty);
      // A transfer category does not stand in the way.
      final moved = moneyOut(
        1,
        kes(13050),
        categoryType: CategoryType.transfer,
      );
      expect(pairs([moved, into]), hasLength(1));
    });

    test('money typed in by hand, unless the person said where it went', () {
      final typed = moneyIn(2, usd(100), source: TransactionSource.manual);
      expect(pairs([out, typed]), isEmpty);
      final typedAndNamed = moneyIn(
        2,
        usd(100),
        source: TransactionSource.manual,
        from: shillings,
      );
      expect(pairs([out, typedAndNamed]), hasLength(1));
    });

    test('a side already paired', () {
      final paired = moneyOut(1, kes(13050), pairedWith: 77);
      expect(pairs([paired, into]), isEmpty);
      expect(suggest(into, [paired, into]), isEmpty);
      expect(suggest(paired, [paired, into]), isEmpty);
    });

    test('a pair the person unmatched', () {
      final declined = {const TransferPair(1, 2)};
      expect(pairs([out, into], declined: declined), isEmpty);
      expect(suggest(out, [out, into], declined: declined), isEmpty);
      // Another dollar amount can still take its place.
      final other = moneyIn(3, usd(100), minute: 5);
      expect(pairs([out, into, other], declined: declined), [
        const TransferPair(1, 3),
      ]);
    });

    test('an amount of nothing', () {
      expect(pairs([out, moneyIn(2, 0)]), isEmpty);
      expect(suggest(moneyIn(2, 0), [out]), isEmpty);
    });
  });

  group('suggestions, for matching by hand', () {
    test('best first: the closer rate fit, then the closest in time', () {
      final out = moneyOut(1, kes(12920));
      final loose = moneyIn(2, usd(93), minute: 1);
      final later = moneyIn(3, usd(100), at: eat(2026, 11, 22, 9));
      final sooner = moneyIn(4, usd(99), accountId: otherBank, minute: 5);
      final offered = suggest(out, [out, loose, later, sooner]);
      expect([for (final s in offered) s.inflow.id], [4, 3, 2]);
      expect(
        [for (final s in offered) s.fit],
        [
          CrossCurrencyFit.atRate,
          CrossCurrencyFit.atRate,
          CrossCurrencyFit.loose,
        ],
      );
    });

    test('for money in, the other side is money out', () {
      final into = moneyIn(2, usd(100));
      final out = moneyOut(1, kes(13050), accountId: mpesa, minute: 1);
      final offered = suggest(into, [into, out]).single;
      expect(offered.pair, const TransferPair(1, 2));
      expect(offered.partnerOf(into), same(out));
    });

    test('no more than the limit', () {
      final out = moneyOut(1, kes(12920));
      final many = [
        for (var i = 0; i < 5; i++) moneyIn(10 + i, usd(100), minute: i + 1),
      ];
      expect(suggest(out, [out, ...many]), hasLength(3));
      expect(suggest(out, [out, ...many], limit: 1).single.inflow.id, 10);
    });

    test('money typed in by hand can be chosen', () {
      final out = moneyOut(1, kes(13050));
      final typed = moneyIn(
        2,
        usd(100),
        accountId: byHand,
        source: TransactionSource.manual,
      );
      expect(suggest(out, [out, typed]), hasLength(1));
    });

    test('the entry itself may be any kind the person says it was', () {
      // A paybill payment filed under an expense: the person knows better.
      final out = moneyOut(
        1,
        kes(13050),
        accountId: mpesa,
        kind: TransactionKind.till,
        categoryType: CategoryType.expense,
      );
      final into = moneyIn(2, usd(100));
      expect(suggest(out, [out, into]), hasLength(1));
      // But the other side must be one a transfer comes as.
      expect(suggest(into, [out, into]), isEmpty);
    });
  });

  group("the app's own rates", () {
    ExchangeRates usdRates(double kes, DateTime at) => ExchangeRates.fromJson({
      'base': 'USD',
      'rates': {'KES': kes, 'EUR': 0.92},
    }, fetchedAt: at)!;
    final history = RateHistory([
      DayRates(
        CalendarDate(2026, 11, 18),
        usdRates(128.4, DateTime.utc(2026, 11, 18, 5)),
      ),
      DayRates(
        CalendarDate(2026, 11, 21),
        usdRates(129.2, DateTime.utc(2026, 11, 21, 5)),
      ),
    ]);
    final rateOn = dayRatesOf(CurrencyConverter(base: 'KES', history: history));

    test('the rates kept for the day, through the base currency', () {
      final at = eat(2026, 11, 21, 10);
      final toShillings = rateOn('USD', 'KES', at)!;
      expect(toShillings.rate, closeTo(129.2, 1e-9));
      expect(toShillings.approximate, isFalse);
      expect(rateOn('KES', 'USD', at)!.rate, closeTo(1 / 129.2, 1e-12));
      expect(rateOn('USD', 'EUR', at)!.rate, closeTo(0.92, 1e-9));
      expect(rateOn('KES', 'KES', at)!.rate, 1);
    });

    test("else the closest earlier day's", () {
      final quote = rateOn('USD', 'KES', eat(2026, 11, 20, 10))!;
      expect(quote.rate, closeTo(128.4, 1e-9));
      expect(quote.approximate, isFalse);
    });

    test('before any were kept, the oldest, marked approximate', () {
      final quote = rateOn('USD', 'KES', eat(2026, 10, 2, 10))!;
      expect(quote.rate, closeTo(128.4, 1e-9));
      expect(quote.approximate, isTrue);
    });

    test('none for a currency the rates do not list, or with no rates', () {
      expect(rateOn('USD', 'XAF', eat(2026, 11, 21, 10)), isNull);
      final empty = dayRatesOf(const CurrencyConverter(base: 'KES'));
      expect(empty('USD', 'KES', eat(2026, 11, 21, 10)), isNull);
    });

    test("the person's own rate wins", () {
      final own = dayRatesOf(
        CurrencyConverter(
          base: 'KES',
          history: history,
          // One shilling buys this many dollars: 1 USD = 131 KES.
          ownRates: const {'USD': 1 / 131},
        ),
      );
      final quote = own('USD', 'KES', eat(2026, 11, 21, 10))!;
      expect(quote.rate, closeTo(131, 1e-9));
      expect(quote.approximate, isFalse);
    });

    test('pairs the example with the rates the app keeps', () {
      final found = findCrossCurrencyTransfers(
        [moneyOut(1, kes(13050)), moneyIn(2, usd(100))],
        accounts: accounts,
        rateOn: rateOn,
      ).single;
      expect(found.pair, const TransferPair(1, 2));
      expect(found.costIn('KES', rateOn), kes(130));
    });

    test('a move from before rates were kept is offered, cost unknown', () {
      // 2 October: the app has only later rates, and the pair's own rate
      // (1 USD = 150 KES) is far from them.
      final out = moneyOut(1, kes(15000), at: eat(2026, 10, 2, 10));
      final into = moneyIn(2, usd(100), at: eat(2026, 10, 2, 10, 2));
      expect(
        findCrossCurrencyTransfers(
          [out, into],
          accounts: accounts,
          rateOn: rateOn,
        ),
        isEmpty,
      );
      final offered = suggestCrossCurrencyPartners(
        out,
        [out, into],
        accounts: accounts,
        rateOn: rateOn,
      ).single;
      expect(offered.fit, CrossCurrencyFit.unchecked);
      expect(offered.costIn('KES', rateOn), isNull);
    });
  });
}
