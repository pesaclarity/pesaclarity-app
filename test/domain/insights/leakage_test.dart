import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/health/health_inputs.dart';
import 'package:pesaclarity/src/domain/insights/insights_summary.dart';
import 'package:pesaclarity/src/domain/insights/leakage.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/plan/month_plan.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

final october = YearMonth(2026, 10);
final september = YearMonth(2026, 9);

LedgerEntry leak(LeakType type, int shillings, DateTime at, {int fee = 0}) =>
    entry(
      at: at,
      amount: kes(shillings),
      leakType: type,
      payeeId: 9,
      categoryType: CategoryType.expense,
      fee: fee,
    );

final history = [
  // Salary.
  inflow(
    at: eat(2026, 10, 25),
    amount: kes(100000),
    categoryType: CategoryType.income,
  ),
  inflow(
    at: eat(2026, 9, 25),
    amount: kes(100000),
    categoryType: CategoryType.income,
  ),
  leak(LeakType.lifestyle, 12000, eat(2026, 10, 3), fee: kes(30)),
  leak(LeakType.lifestyle, 4200, eat(2026, 10, 17)),
  leak(LeakType.friends, 7400, eat(2026, 10, 9)),
  leak(LeakType.family, 5300, eat(2026, 10, 12)),
  leak(LeakType.fees, 200, eat(2026, 10, 12)),
  // Ordinary spending is not a leak, but its transaction cost is.
  entry(
    at: eat(2026, 10, 5),
    amount: kes(25000),
    categoryType: CategoryType.expense,
    fee: kes(70),
  ),
  // A bank charge.
  entry(at: eat(2026, 10, 30), amount: kes(400), kind: TransactionKind.charge),
  // A Fuliza draw on 30 September repaid in October with 300 in fees.
  inflow(
    at: eat(2026, 9, 30),
    amount: kes(2000),
    kind: TransactionKind.fulizaDraw,
  ),
  entry(
    at: eat(2026, 10, 2),
    amount: kes(2300),
    kind: TransactionKind.fulizaRepayment,
  ),
  // A refund from a lifestyle payee does not reduce leakage.
  inflow(
    at: eat(2026, 10, 20),
    amount: kes(1000),
    kind: TransactionKind.reversal,
  ),
  // September leakage.
  leak(LeakType.lifestyle, 10900, eat(2026, 9, 10)),
];

void main() {
  test('groups leakages and splits Fuliza fees from other fees', () {
    final b = LeakageBreakdown.of(
      history,
      from: october.startInstant,
      to: october.endInstant,
    );
    expect(b.lifestyleMinor, kes(16200));
    expect(b.friendsMinor, kes(7400));
    expect(b.familyMinor, kes(5300));
    expect(b.feesMinor, kes(200 + 30 + 70 + 400));
    expect(b.fulizaMinor, kes(300));
    expect(b.totalMinor, kes(16200 + 7400 + 5300 + 700 + 300));
    expect(b.groups.map((g) => g.label), [
      'Lifestyle',
      'Friends',
      'Family',
      'Fees',
      'Fuliza fees',
    ]);
  });

  test('matches the leakage the Financial Health Index scores', () {
    final plan = MonthPlan.build(
      month: october,
      recurring: const [],
      items: const [],
      categories: const [],
    );
    final inputs = HealthInputs.forMonth(plan: plan, history: history);
    final b = LeakageBreakdown.of(
      history,
      from: october.startInstant,
      to: october.endInstant,
    );
    expect(b.totalMinor, inputs.leakageMinor);
  });

  test('leaves out other currencies and entries outside the period', () {
    final b = LeakageBreakdown.of(
      [
        leak(LeakType.lifestyle, 100, eat(2026, 11, 1)),
        entry(
          at: eat(2026, 10, 3),
          amount: 5000,
          currency: 'USD',
          leakType: LeakType.lifestyle,
        ),
      ],
      from: october.startInstant,
      to: october.endInstant,
    );
    expect(b.totalMinor, 0);
  });

  test('percentLabel rounds half up', () {
    expect(percentLabel(1749), '17%');
    expect(percentLabel(1750), '18%');
    expect(shareBasisPoints(kes(30100), kes(177000)), 1700);
    expect(shareBasisPoints(1, 0), isNull);
  });

  group('InsightsSummary', () {
    final summary = InsightsSummary.of(history, month: october);

    test('covers six months, oldest first', () {
      expect(summary.trend.map((m) => m.month.month), [5, 6, 7, 8, 9, 10]);
      expect(summary.current.month, october);
      expect(summary.previous!.month, september);
      expect(summary.hasData, isTrue);
    });

    test('compares leakage with last month and halves it', () {
      expect(summary.current.leakageMinor, kes(29900));
      expect(summary.current.leakageShareBasisPoints, 2990);
      expect(summary.previous!.leakageMinor, kes(10900));
      expect(summary.leakageChangeMinor, kes(19000));
      // 14,950 rounded down to the nearest 100.
      expect(summary.halfLeakageMinor, kes(14900));
    });

    test('counts spending with fees per month', () {
      // 16,200 + 7,400 + 5,300 + 200 + 25,000 spending, less the 1,000
      // refund, plus 800 in fees (100 transaction costs, the 400 charge and
      // 300 of Fuliza fees).
      expect(summary.current.spendingMinor, kes(53900));
      expect(summary.previous!.spendingMinor, kes(10900));
      expect(summary.trend.first.spendingMinor, 0);
    });

    test('has no data with no entries', () {
      expect(InsightsSummary.of(const [], month: october).hasData, isFalse);
    });
  });
}
