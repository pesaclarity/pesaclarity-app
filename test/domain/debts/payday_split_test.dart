import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/debts/debt.dart';
import 'package:pesaclarity/src/domain/debts/payday_split.dart';
import 'package:pesaclarity/src/domain/debts/payoff_order.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

final nov = YearMonth(2026, 11);

Debt card({int balance = 50000}) => Debt(
  id: 1,
  lender: 'Test Card',
  type: DebtType.card,
  balanceMinor: balance,
  annualRateBasisPoints: 3600,
  minimumPaymentMinor: 2000,
);

Debt mobile({int balance = 20000}) => Debt(
  id: 2,
  lender: 'Test Mobile Loan',
  type: DebtType.mobileLoan,
  balanceMinor: balance,
  annualRateBasisPoints: 1200,
  minimumPaymentMinor: 1000,
);

Map<int, (int, int)> sharesOf(PaydaySplit split) => {
  for (final s in split.shares) s.debtId: (s.minimumMinor, s.extraMinor),
};

void main() {
  test('minimums first, the rest to the avalanche target', () {
    final split = PaydaySplit.of(
      debts: [card(), mobile()],
      availableMinor: 10000,
      month: nov,
    );
    expect(sharesOf(split), {1: (2000, 7000), 2: (1000, 0)});
    expect(split.targetDebtId, 1);
    expect(split.totalMinor, 10000);
    expect(split.shortfallMinor, 0);
  });

  test('snowball targets the smallest balance', () {
    final split = PaydaySplit.of(
      debts: [card(), mobile()],
      availableMinor: 10000,
      month: nov,
      strategy: PayoffStrategy.snowball,
    );
    expect(sharesOf(split), {2: (1000, 7000), 1: (2000, 0)});
    expect(split.targetDebtId, 2);
  });

  test('a cleared target passes the rest down the order', () {
    final split = PaydaySplit.of(
      debts: [card(balance: 3000), mobile()],
      availableMinor: 10000,
      month: nov,
    );
    expect(sharesOf(split), {1: (2000, 1000), 2: (1000, 6000)});
    expect(split.targetDebtId, 1);
  });

  test('money short of the minimums is a shortfall', () {
    final split = PaydaySplit.of(
      debts: [card(), mobile()],
      availableMinor: 2500,
      month: nov,
    );
    expect(sharesOf(split), {1: (2000, 0), 2: (500, 0)});
    expect(split.shortfallMinor, 500);
    expect(split.targetDebtId, 1);
  });

  test('money left once everything is cleared is unallocated', () {
    final split = PaydaySplit.of(
      debts: [card(balance: 1500), mobile(balance: 500)],
      availableMinor: 10000,
      month: nov,
    );
    expect(split.totalMinor, 2000);
    expect(split.unallocatedMinor, 8000);
  });

  test('includes missed family instalments', () {
    final family = Debt(
      id: 3,
      lender: 'Test Aunt',
      type: DebtType.family,
      balanceMinor: 9000,
      instalments: [
        DebtInstalment(dueDate: CalendarDate(2026, 10, 1), amountMinor: 3000),
        DebtInstalment(dueDate: CalendarDate(2026, 11, 1), amountMinor: 3000),
        DebtInstalment(dueDate: CalendarDate(2026, 12, 1), amountMinor: 3000),
      ],
    );
    final split = PaydaySplit.of(
      debts: [family],
      availableMinor: 6000,
      month: nov,
    );
    expect(sharesOf(split), {3: (6000, 0)});
    expect(split.targetDebtId, 3);
  });

  test('no money still names the target', () {
    final split = PaydaySplit.of(
      debts: [card(), mobile()],
      availableMinor: 0,
      month: nov,
      customOrder: [2],
      strategy: PayoffStrategy.custom,
    );
    expect(split.shares, isEmpty);
    expect(split.targetDebtId, 2);
    expect(split.shortfallMinor, 3000);
  });
}
