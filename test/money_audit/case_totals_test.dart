import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_totals.dart';

import '../domain/fixtures.dart';

/// One made-up entry per case the money totals must get right, each with
/// the figure it must leave in the month's totals.
void main() {
  final from = eat(2026, 11, 1, 0);
  final to = eat(2026, 12, 1, 0);
  LedgerTotals totals(List<LedgerEntry> list) =>
      LedgerTotals.of(list, from: from, to: to);
  final day = eat(2026, 11, 10);

  test('bank: card purchase, charge, salary, loan in and out, interest', () {
    final t = totals([
      entry(at: day, amount: kes(2500), kind: TransactionKind.bank),
      entry(at: day, amount: kes(55), kind: TransactionKind.charge),
      inflow(
        at: day,
        amount: kes(60000),
        kind: TransactionKind.bank,
        payeeId: 1,
        categoryType: CategoryType.income,
      ),
      // A loan paid out to the account: owed back, never income.
      inflow(
        at: day,
        amount: kes(20000),
        kind: TransactionKind.bank,
        payeeId: 2,
        categoryType: CategoryType.debt,
      ),
      entry(at: day, amount: kes(4000), kind: TransactionKind.loanRepayment),
      inflow(
        at: day,
        amount: kes(120),
        kind: TransactionKind.bank,
        payeeId: 3,
        categoryType: CategoryType.income,
      ),
    ]);
    expect(t.spendingMinor, kes(2500));
    expect(t.feesMinor, kes(55));
    expect(t.incomeMinor, kes(60000) + kes(120));
    expect(t.moneyInMinor, kes(60000) + kes(120));
    expect(t.borrowingMinor, kes(20000));
    expect(t.debtRepaymentMinor, kes(4000));
  });

  test('own moves: lines, SACCO, Pochi, KCB M-Pesa never in or out', () {
    final t = totals([
      // Between the person's two M-Pesa lines, fee 7.
      entry(
        at: day,
        amount: kes(1000),
        kind: TransactionKind.sent,
        fee: kes(7),
        transferPairId: 101,
        id: 100,
      ),
      inflow(at: day, amount: kes(1000), id: 101).copyWith(transferPairId: 100),
      // Into a SACCO of theirs: saved.
      entry(
        at: day,
        amount: kes(3000),
        kind: TransactionKind.paybill,
        categoryType: CategoryType.savings,
        transferPairId: 900,
      ),
      // Into their own Pochi la Biashara and KCB M-Pesa.
      entry(
        at: day,
        amount: kes(500),
        kind: TransactionKind.sent,
        transferPairId: 800,
      ),
      entry(
        at: day,
        amount: kes(800),
        kind: TransactionKind.paybill,
        categoryType: CategoryType.transfer,
      ),
    ]);
    expect(t.spendingMinor, 0);
    expect(t.incomeMinor, 0);
    expect(t.moneyInMinor, 0);
    expect(t.feesMinor, kes(7));
    expect(t.savingMinor, kes(3000));
    expect(t.ownTransferMinor, kes(1000) + kes(500) + kes(800));
  });

  test('a balance set by hand is never income or spending', () {
    final t = totals([
      inflow(at: day, amount: kes(900), kind: TransactionKind.correction),
      entry(at: day, amount: kes(300), kind: TransactionKind.correction),
    ]);
    expect(t.incomeMinor, 0);
    expect(t.moneyInMinor, 0);
    expect(t.spendingMinor, 0);
    expect(t.feesMinor, 0);
  });

  test('airtime for self or others is spending, once', () {
    final t = totals([
      entry(at: day, amount: kes(100), kind: TransactionKind.airtime),
      entry(at: day, amount: kes(50), kind: TransactionKind.airtime),
    ]);
    expect(t.spendingMinor, kes(150));
  });

  test('another currency stays out of the shilling totals', () {
    final t = totals([
      entry(at: day, amount: 4250, currency: 'USD'),
      entry(at: day, amount: kes(5500)),
    ]);
    expect(t.spendingMinor, kes(5500));
  });
}
