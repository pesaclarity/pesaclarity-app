import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/fuliza.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

LedgerEntry draw(DateTime at, int amount, {int? id}) =>
    inflow(id: id, kind: TransactionKind.fulizaDraw, at: at, amount: amount);

LedgerEntry repay(DateTime at, int amount, {int? id}) => entry(
  id: id,
  kind: TransactionKind.fulizaRepayment,
  at: at,
  amount: amount,
);

void main() {
  test('the fee is repayments minus draws over a cycle', () {
    final r = repay(eat(2026, 10, 6), kes(1010));
    final ledger = FulizaLedger.of([draw(eat(2026, 10, 5), kes(1000)), r]);
    expect(ledger.feeOf(r), kes(10));
    expect(ledger.outstandingMinor, 0);
  });

  test('partial repayments clear the draw before any fee', () {
    final r1 = repay(eat(2026, 10, 6), kes(600));
    final r2 = repay(eat(2026, 10, 7), kes(430));
    final ledger = FulizaLedger.of([
      draw(eat(2026, 10, 5, 8), kes(500)),
      draw(eat(2026, 10, 5, 9), kes(500)),
      r1,
      r2,
    ]);
    expect(ledger.feeOf(r1), 0);
    expect(ledger.feeOf(r2), kes(30));
  });

  test('a draw repaid next month gives no negative fee in either month', () {
    final entries = [
      draw(eat(2026, 10, 31, 23, 30), kes(800)),
      repay(eat(2026, 11, 1, 0, 30), kes(808)),
    ];
    final ledger = FulizaLedger.of(entries);

    final october = ledger.month(entries, YearMonth(2026, 10));
    expect(october.drawsMinor, kes(800));
    expect(october.drawCount, 1);
    expect(october.repaymentsMinor, 0);
    expect(october.feesMinor, 0);

    final november = ledger.month(entries, YearMonth(2026, 11));
    expect(november.drawsMinor, 0);
    expect(november.repaymentsMinor, kes(808));
    expect(november.feesMinor, kes(8));
    expect(ledger.outstandingMinor, 0);
  });

  test('a draw still outstanding at month end leaves the fee for later', () {
    final entries = [
      draw(eat(2026, 10, 20), kes(2000)),
      repay(eat(2026, 10, 25), kes(500)),
    ];
    final ledger = FulizaLedger.of(entries);
    expect(ledger.month(entries, YearMonth(2026, 10)).feesMinor, 0);
    expect(ledger.outstandingMinor, kes(1500));
  });

  test('a repayment with no earlier draw counts as fee', () {
    final r = repay(eat(2026, 10, 1), kes(50));
    expect(FulizaLedger.of([r]).feeOf(r), kes(50));
  });

  test('a draw and repayment at the same instant applies the draw first', () {
    final at = eat(2026, 10, 5);
    final r = repay(at, kes(105), id: 1);
    final ledger = FulizaLedger.of([r, draw(at, kes(100), id: 2)]);
    expect(ledger.feeOf(r), kes(5));
  });

  test('ignores other entries and gives zero fee for them', () {
    final other = entry(at: eat(2026, 10, 5), amount: kes(100));
    expect(FulizaLedger.of([other]).feeOf(other), 0);
  });

  test('totals split repayments into fee and debt repayment', () {
    final entries = [
      draw(eat(2026, 9, 28), kes(1000)),
      repay(eat(2026, 10, 2), kes(1015)),
      draw(eat(2026, 10, 10), kes(300)),
      repay(eat(2026, 10, 12), kes(303)),
    ];
    final totals = LedgerTotals.of(
      entries,
      from: YearMonth(2026, 10).startInstant,
      to: YearMonth(2026, 10).endInstant,
    );
    expect(totals.feesMinor, kes(18));
    expect(totals.debtRepaymentMinor, kes(1300));
    expect(totals.borrowingMinor, kes(300));
    expect(totals.spendingMinor, 0);
    expect(totals.incomeMinor, 0);
  });
}
