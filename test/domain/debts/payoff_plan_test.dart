import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/debts/debt.dart';
import 'package:pesaclarity/src/domain/debts/payoff_order.dart';
import 'package:pesaclarity/src/domain/debts/payoff_plan.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

final nov = YearMonth(2026, 11);

Debt card({int id = 1, int balance = 5000000, int min = 200000}) => Debt(
  id: id,
  lender: 'Test Card',
  type: DebtType.card,
  balanceMinor: balance,
  annualRateBasisPoints: 3600,
  minimumPaymentMinor: min,
);

Debt mobile({int id = 2, int balance = 1000000, int min = 50000}) => Debt(
  id: id,
  lender: 'Test Mobile Loan',
  type: DebtType.mobileLoan,
  balanceMinor: balance,
  annualRateBasisPoints: 1200,
  minimumPaymentMinor: min,
);

void main() {
  group('monthly interest', () {
    test('is a twelfth of the annual rate, rounded half up', () {
      final debt = Debt(
        id: 1,
        lender: 'Test Bank',
        type: DebtType.bankLoan,
        balanceMinor: 1,
        annualRateBasisPoints: 1200,
      );
      expect(debt.monthlyInterestOn(100000), 1000);
      expect(debt.monthlyInterestOn(50), 1, reason: '0.5 rounds up');
      expect(debt.monthlyInterestOn(49), 0, reason: '0.49 rounds down');
      expect(debt.monthlyInterestOn(0), 0);
    });

    test('family loans get none, whatever rate is set', () {
      final debt = Debt(
        id: 1,
        lender: 'Test Aunt',
        type: DebtType.family,
        balanceMinor: 100000,
        annualRateBasisPoints: 1200,
      );
      expect(debt.isFormal, isFalse);
      expect(debt.monthlyInterestOn(100000), 0);
    });

    test('a loan marked informal is treated like family', () {
      final debt = Debt(
        id: 1,
        lender: 'Test Friend',
        type: DebtType.salaryAdvance,
        balanceMinor: 100000,
        annualRateBasisPoints: 1200,
        isFormal: false,
      );
      expect(debt.chargesInterest, isFalse);
    });
  });

  group('payoff order', () {
    final debts = [card(), mobile()];

    test('avalanche puts the highest rate first', () {
      expect(payoffOrder(debts, PayoffStrategy.avalanche).map((d) => d.id), [
        1,
        2,
      ]);
    });

    test('snowball puts the smallest balance first', () {
      expect(payoffOrder(debts, PayoffStrategy.snowball).map((d) => d.id), [
        2,
        1,
      ]);
    });

    test('ties fall back to balance or rate, then id', () {
      final same = [
        mobile(id: 5, balance: 2000),
        mobile(id: 3, balance: 2000),
        mobile(id: 4, balance: 1000),
      ];
      expect(payoffOrder(same, PayoffStrategy.avalanche).map((d) => d.id), [
        4,
        3,
        5,
      ]);
      expect(payoffOrder(same, PayoffStrategy.snowball).map((d) => d.id), [
        4,
        3,
        5,
      ]);
    });

    test('custom follows the given ids, the rest in avalanche order', () {
      final three = [card(), mobile(), mobile(id: 3, balance: 10)];
      expect(
        payoffOrder(
          three,
          PayoffStrategy.custom,
          customOrder: [2],
        ).map((d) => d.id),
        [2, 1, 3],
      );
    });

    test('a chosen first debt goes first under any strategy', () {
      expect(
        payoffOrder(
          debts,
          PayoffStrategy.avalanche,
          firstDebtId: 2,
        ).map((d) => d.id),
        [2, 1],
      );
    });

    test('family loans without interest come last under avalanche', () {
      final family = Debt(
        id: 9,
        lender: 'Test Uncle',
        type: DebtType.family,
        balanceMinor: 100,
        annualRateBasisPoints: 9900,
      );
      expect(
        payoffOrder([family, ...debts], PayoffStrategy.avalanche).last.id,
        9,
      );
    });
  });

  group('simulation', () {
    test('matches a hand-worked schedule', () {
      final debt = Debt(
        id: 1,
        lender: 'Test Bank',
        type: DebtType.bankLoan,
        balanceMinor: 100000,
        annualRateBasisPoints: 1200,
        minimumPaymentMinor: 50000,
      );
      final plan = PayoffPlan.simulate([debt], PayoffOptions(startMonth: nov));

      // 100000 + 1000 - 50000 = 51000; + 510 - 50000 = 1510;
      // + 15 (15.1 rounded) = 1525, paid in full.
      expect(plan.months.map((m) => m.remainingMinor), [51000, 1510, 0]);
      expect(plan.months.map((m) => m.interestMinor), [1000, 510, 15]);
      expect(plan.totalInterestMinor, 1525);
      expect(plan.totalPaidMinor, 101525);
      expect(plan.debt(1).paidOffIn, YearMonth(2027, 1));
      expect(plan.debtFreeMonth, YearMonth(2027, 1));
    });

    test('zero interest pays down in whole minimums', () {
      final debt = Debt(
        id: 1,
        lender: 'Test SACCO',
        type: DebtType.saccoLoan,
        balanceMinor: 10000,
        minimumPaymentMinor: 3000,
      );
      final plan = PayoffPlan.simulate([debt], PayoffOptions(startMonth: nov));
      expect(plan.months.map((m) => m.paidMinor[1]), [3000, 3000, 3000, 1000]);
      expect(plan.totalInterestMinor, 0);
      expect(plan.debtFreeMonth, YearMonth(2027, 2));
    });

    test('a cleared minimum rolls on to the next debt', () {
      final debts = [
        Debt(
          id: 1,
          lender: 'Test A',
          type: DebtType.mobileLoan,
          balanceMinor: 3000,
          minimumPaymentMinor: 1000,
        ),
        Debt(
          id: 2,
          lender: 'Test B',
          type: DebtType.mobileLoan,
          balanceMinor: 10000,
          minimumPaymentMinor: 1000,
        ),
      ];
      final comparison = PayoffComparison.againstMinimums(
        debts,
        PayoffOptions(startMonth: nov, strategy: PayoffStrategy.snowball),
      );
      final plan = comparison.plan;
      expect(plan.debt(1).paidOffIn, YearMonth(2027, 1));
      expect(plan.months.map((m) => m.balancesMinor[2]), [
        9000,
        8000,
        7000,
        5000,
        3000,
        1000,
        0,
      ]);
      expect(plan.debtFreeMonth, YearMonth(2027, 5));
      expect(comparison.baseline.debtFreeMonth, YearMonth(2027, 8));
      expect(comparison.monthsSooner, 3);
      expect(comparison.interestSavedMinor, 0);
    });

    test('avalanche costs less interest; snowball clears a debt sooner', () {
      final debts = [card(), mobile()];
      final options = PayoffOptions(startMonth: nov, extraMonthlyMinor: 300000);
      final avalanche = PayoffPlan.simulate(debts, options);
      final snowball = PayoffPlan.simulate(
        debts,
        options.copyWith(strategy: PayoffStrategy.snowball),
      );

      expect(avalanche.order, [1, 2]);
      expect(snowball.order, [2, 1]);
      expect(
        avalanche.totalInterestMinor,
        lessThan(snowball.totalInterestMinor),
      );
      expect(
        snowball.debt(2).paidOffIn!.compareTo(avalanche.debt(2).paidOffIn!),
        lessThan(0),
      );
      expect(
        snowball.debt(2).paidOffIn!.compareTo(snowball.debt(1).paidOffIn!),
        lessThan(0),
      );
      for (final plan in [avalanche, snowball]) {
        expect(plan.clearsAll, isTrue);
        final monthly = plan.months
            .take(plan.months.length - 1)
            .map((m) => m.paidMinor.values.fold(0, (a, b) => a + b));
        expect(monthly.toSet(), {550000}, reason: 'minimums plus extra');
        final debtSum = debts.fold(0, (s, d) => s + d.balanceMinor);
        expect(plan.totalPaidMinor, debtSum + plan.totalInterestMinor);
      }
    });

    test('reports a debt that never clears at its minimum', () {
      // 3% a month on 1,000 KES is 30 KES, more than the 20 KES minimum.
      final growing = card(balance: 100000, min: 2000);
      final comparison = PayoffComparison.againstMinimums([
        growing,
        mobile(),
      ], PayoffOptions(startMonth: nov, horizonMonths: 120));

      final baseline = comparison.baseline;
      expect(baseline.neverClears, [1]);
      expect(baseline.clearsAll, isFalse);
      expect(baseline.debtFreeMonth, isNull);
      expect(baseline.debtFreeOn(28), isNull);
      expect(baseline.months, hasLength(120));
      expect(baseline.debt(1).remainingMinor, greaterThan(100000));
      expect(baseline.debt(2).clears, isTrue);

      // Rolling the mobile loan's minimum over is enough to clear it.
      expect(comparison.plan.clearsAll, isTrue);
      expect(comparison.onlyPlanClears, isTrue);
      expect(comparison.interestSavedMinor, isNull);
      expect(comparison.monthsSooner, isNull);
    });

    test('nothing owed means nothing to plan', () {
      final plan = PayoffPlan.simulate([
        card(balance: 0),
      ], PayoffOptions(startMonth: nov));
      expect(plan.debts, isEmpty);
      expect(plan.months, isEmpty);
      expect(plan.clearsAll, isTrue);
      expect(plan.debtFreeMonth, isNull);
    });

    test('the debt-free date falls on payday, clamped to short months', () {
      final debt = Debt(
        id: 1,
        lender: 'Test SACCO',
        type: DebtType.saccoLoan,
        balanceMinor: 3000,
        minimumPaymentMinor: 1000,
      );
      final plan = PayoffPlan.simulate([
        debt,
      ], PayoffOptions(startMonth: YearMonth(2026, 12)));
      expect(plan.debtFreeMonth, YearMonth(2027, 2));
      expect(plan.debtFreeOn(31), CalendarDate(2027, 2, 28));
      expect(plan.debtFreeOn(15), CalendarDate(2027, 2, 15));
    });

    test('family instalments are paid as agreed, with no interest', () {
      final family = Debt(
        id: 1,
        lender: 'Test Aunt',
        type: DebtType.family,
        balanceMinor: kes(250),
        annualRateBasisPoints: 1200,
        instalments: [
          DebtInstalment(
            dueDate: CalendarDate(2026, 10, 30),
            amountMinor: kes(50),
          ),
          DebtInstalment(
            dueDate: CalendarDate(2026, 11, 15),
            amountMinor: kes(50),
          ),
          DebtInstalment(
            dueDate: CalendarDate(2027, 1, 15),
            amountMinor: kes(150),
          ),
        ],
      );
      final plan = PayoffPlan.simulate([
        family,
      ], PayoffOptions(startMonth: nov));
      expect(plan.months.map((m) => m.paidMinor[1] ?? 0), [
        kes(100),
        0,
        kes(150),
      ], reason: 'October is overdue and caught up in November');
      expect(plan.totalInterestMinor, 0);
      expect(plan.debtFreeMonth, YearMonth(2027, 1));
    });

    test('a family loan with no plan and no extra never clears', () {
      final family = Debt(
        id: 1,
        lender: 'Test Uncle',
        type: DebtType.family,
        balanceMinor: kes(100),
      );
      final plan = PayoffPlan.simulate([
        family,
      ], PayoffOptions(startMonth: nov, horizonMonths: 12));
      expect(plan.neverClears, [1]);
    });
  });

  group('what-if', () {
    final debts = [card(), mobile()];
    final base = PayoffOptions(startMonth: nov, extraMonthlyMinor: 100000);

    test('adding 5,000 a month brings the date forward and saves interest', () {
      final whatIf = PayoffComparison.whatIf(
        debts,
        base: base,
        scenario: base.copyWith(extraMonthlyMinor: 100000 + kes(5000)),
      );
      expect(whatIf.monthsSooner, greaterThan(0));
      expect(whatIf.interestSavedMinor, greaterThan(0));
    });

    test('clearing a chosen debt first recalculates the order', () {
      final whatIf = PayoffComparison.whatIf(
        debts,
        base: base,
        scenario: base.copyWith(firstDebtId: 2),
      );
      expect(whatIf.plan.order, [2, 1]);
      expect(
        whatIf.plan
            .debt(2)
            .paidOffIn!
            .compareTo(whatIf.baseline.debt(2).paidOffIn!),
        lessThan(0),
      );
      expect(whatIf.interestSavedMinor, lessThan(0), reason: 'avalanche wins');
    });

    test('the same options make no difference', () {
      final whatIf = PayoffComparison.whatIf(debts, base: base, scenario: base);
      expect(whatIf.monthsSooner, 0);
      expect(whatIf.interestSavedMinor, 0);
    });
  });
}
