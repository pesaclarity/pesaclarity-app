// What an own transfer across currencies cost to exchange, as the figures
// count it: with fees, on the day the money arrived, and a gain lowers
// fees. Synthetic data only.
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/insights/leakage.dart';
import 'package:pesaclarity/src/domain/insights/spending_charts.dart';
import 'package:pesaclarity/src/domain/ledger/activity_feed.dart';
import 'package:pesaclarity/src/domain/ledger/cross_currency_transfers.dart';
import 'package:pesaclarity/src/domain/ledger/fuliza.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';

import '../fixtures.dart';

/// KES 13,050 out on the 20th; USD 100.00 in, read as KES 12,920, on the
/// 21st: both read in the base, as the app reads them.
LedgerEntry out({int amount = 1305000, int? pair = 2, int fee = 0}) =>
    LedgerEntry(
      id: 1,
      accountId: 1,
      occurredAt: eat(2026, 11, 20, 23),
      amountMinor: amount,
      direction: TransactionDirection.outflow,
      kind: TransactionKind.bank,
      currency: 'KES',
      feeMinor: fee,
      transferPairId: pair,
    );

LedgerEntry into({
  int amount = 1292000,
  int? pair = 1,
  String? movedIn = 'USD',
  int? cost,
}) => LedgerEntry(
  id: 2,
  accountId: 2,
  occurredAt: eat(2026, 11, 21, 10, 2),
  amountMinor: amount,
  direction: TransactionDirection.inflow,
  kind: TransactionKind.bank,
  currency: 'KES',
  transferPairId: pair,
  originalAmountMinor: movedIn == null ? null : 10000,
  originalCurrency: movedIn,
  exchangeCostMinor: cost,
);

void main() {
  group('exchangeCostOf', () {
    test('the money out less the money in, both read in the base', () {
      expect(exchangeCostOf(out(), into()), kes(130));
      expect(exchangeCostBasisPoints(out(), into()), 100);
      expect(rateGotOf(out(), into()), closeTo(1 / 130.5, 1e-12));
    });

    test('negative when more came in', () {
      expect(exchangeCostOf(out(amount: kes(12900)), into()), -kes(20));
    });

    test('nothing for one currency, an unpaired side, or a side left in '
        'its own currency for want of a rate', () {
      expect(exchangeCostOf(out(), into(movedIn: null)), isNull);
      expect(exchangeCostOf(out(pair: null), into()), isNull);
      final unconverted = LedgerEntry(
        id: 2,
        accountId: 2,
        occurredAt: eat(2026, 11, 21, 10, 2),
        amountMinor: 10000,
        direction: TransactionDirection.inflow,
        kind: TransactionKind.bank,
        currency: 'USD',
        transferPairId: 1,
      );
      expect(isCrossCurrencyPair(out(), unconverted), isTrue);
      expect(exchangeCostOf(out(), unconverted), isNull);
    });
  });

  group('the figures', () {
    final history = [out(fee: kes(50)), into(cost: kes(130))];

    test('the cost counts with fees, on the day the money arrived; the '
        'transfer is neither spending nor income', () {
      final day = LedgerTotals.of(
        history,
        from: eat(2026, 11, 21, 0),
        to: eat(2026, 11, 22, 0),
      );
      expect(day.feesMinor, kes(130));
      expect(day.spendingMinor, 0);
      expect(day.incomeMinor, 0);
      final dayBefore = LedgerTotals.of(
        history,
        from: eat(2026, 11, 20, 0),
        to: eat(2026, 11, 21, 0),
      );
      // Only the fee the message printed, with the money out.
      expect(dayBefore.feesMinor, kes(50));
      expect(dayBefore.ownTransferMinor, kes(13050));
    });

    test('a gain lowers fees and is never income', () {
      final totals = LedgerTotals.of(
        [out(amount: kes(12900)), into(cost: -kes(20))],
        from: eat(2026, 11, 1, 0),
        to: eat(2026, 12, 1, 0),
      );
      expect(totals.feesMinor, -kes(20));
      expect(totals.incomeMinor, 0);
    });

    test('Leakage and the spending chart count it as fees', () {
      final leaks = LeakageBreakdown.of(
        history,
        from: eat(2026, 11, 1, 0),
        to: eat(2026, 12, 1, 0),
      );
      expect(leaks.feesMinor, kes(180));
      expect(spendingPartsOf(history.last, FulizaLedger.of(history)), [
        (const FeesSlice(), kes(130)),
      ]);
    });

    test('the Fees filter on Activity finds it', () {
      expect(ActivityType.fees.matches(history.last), isTrue);
      expect(ActivityType.fees.matches(into()), isFalse);
      expect(ActivityType.moneyIn.matches(history.last), isFalse);
    });
  });
}
