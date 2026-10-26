import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/health/health_index.dart';
import 'package:pesaclarity/src/domain/health/health_inputs.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/plan/month_plan.dart';
import 'package:pesaclarity/src/domain/plan/plan_inputs.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

const salary = 1;
const rent = 2;
const food = 3;
const power = 4;
const loan = 5;
const savings = 6;

const categories = [
  PlanCategory(id: salary, type: CategoryType.income),
  PlanCategory(id: rent, type: CategoryType.expense),
  PlanCategory(id: food, type: CategoryType.expense, isDailySpending: true),
  PlanCategory(id: power, type: CategoryType.expense),
  PlanCategory(id: loan, type: CategoryType.debt),
  PlanCategory(id: savings, type: CategoryType.savings),
];

final october = YearMonth(2026, 10);

RecurringBill monthly(int id, int categoryId, int shillings, int day) =>
    RecurringBill(
      id: id,
      name: 'Bill $id',
      categoryId: categoryId,
      amountMinor: kes(shillings),
      frequency: RecurrenceFrequency.monthly,
      startDate: CalendarDate(2026, 1, day),
    );

final plan = MonthPlan.build(
  month: october,
  recurring: [
    monthly(1, salary, 100000, 25),
    monthly(2, rent, 25000, 5),
    monthly(3, food, 15000, 1),
    monthly(4, power, 2000, 20),
    monthly(5, loan, 10000, 10),
    monthly(6, savings, 8000, 26),
  ],
  items: const [],
  categories: categories,
);

LedgerEntry paid(
  int categoryId,
  int shillings,
  DateTime at, {
  CategoryType type = CategoryType.expense,
  bool daily = false,
  int fee = 0,
}) => entry(
  at: at,
  amount: kes(shillings),
  categoryId: categoryId,
  categoryType: type,
  isDailySpending: daily,
  fee: fee,
);

final history = [
  // Late September: outside the month, so neither income nor a bill payment.
  paid(rent, 25000, eat(2026, 9, 30)),
  inflow(
    at: eat(2026, 10, 25),
    amount: kes(100000),
    categoryId: salary,
    categoryType: CategoryType.income,
  ),
  paid(rent, 25000, eat(2026, 10, 4), fee: kes(30)),
  paid(loan, 10000, eat(2026, 10, 12), type: CategoryType.debt),
  paid(power, 2000, eat(2026, 10, 20, 23)),
  paid(food, 18000, eat(2026, 10, 15), daily: true),
  paid(savings, 8000, eat(2026, 10, 26), type: CategoryType.savings),
  entry(at: eat(2026, 10, 16), amount: kes(3000), leakType: LeakType.lifestyle),
  inflow(
    at: eat(2026, 10, 2, 8),
    amount: kes(300),
    kind: TransactionKind.fulizaDraw,
  ),
  inflow(
    at: eat(2026, 10, 2, 18),
    amount: kes(200),
    kind: TransactionKind.fulizaDraw,
  ),
  inflow(
    at: eat(2026, 10, 3),
    amount: kes(500),
    kind: TransactionKind.fulizaDraw,
  ),
  entry(
    at: eat(2026, 10, 25, 13),
    amount: kes(1010),
    kind: TransactionKind.fulizaRepayment,
  ),
];

void main() {
  group('HealthInputs.forMonth', () {
    test('reads each measure from the ledger and the plan', () {
      final inputs = HealthInputs.forMonth(
        plan: plan,
        history: history,
        savingsBalanceMinor: kes(104000),
      );
      expect(inputs.month, october);
      expect(inputs.incomeMinor, kes(100000));
      expect(inputs.spendingMinor, kes(25000 + 2000 + 18000 + 3000 + 30 + 10));
      expect(inputs.billsDue, 3);
      expect(inputs.billsPaidOnTime, 2);
      expect(inputs.essentialsMinor, kes(25000 + 15000 + 2000 + 10000));
      expect(inputs.savingsBalanceMinor, kes(104000));
      expect(inputs.savedMinor, kes(8000));
      expect(inputs.debtPaymentsMinor, kes(10000 + 1000));
      expect(inputs.overdraftDays, 2);
      expect(inputs.leakageMinor, kes(3000 + 30 + 10));
      expect(inputs.plannedCategories, 3);
      expect(inputs.categoriesWithinBudget, 2);
    });

    test('scores the month end to end', () {
      final index = HealthIndex.compute(
        HealthInputs.forMonth(
          plan: plan,
          history: history,
          savingsBalanceMinor: kes(104000),
        ),
      );
      expect(index.score, 77);
      expect(index.band, HealthBand.healthy);
      expect(index.weakestPillar, HealthPillar.save);
      final action = index.bestAction!;
      expect(action.indicator, HealthIndicator.savingsRate);
      expect(action.gainPoints, 7);
      expect(
        action.message,
        'Save KES 12,000 more a month to reach 20% of income.',
      );
    });

    test('judges only bills due by asOf', () {
      final inputs = HealthInputs.forMonth(
        plan: plan,
        history: history,
        asOf: CalendarDate(2026, 10, 8),
      );
      expect(inputs.billsDue, 1);
      expect(inputs.billsPaidOnTime, 1);
    });

    test('a bill paid in parts is on time only once fully paid', () {
      final inputs = HealthInputs.forMonth(
        plan: plan,
        history: [
          paid(rent, 20000, eat(2026, 10, 3)),
          paid(rent, 5000, eat(2026, 10, 6)),
        ],
        asOf: CalendarDate(2026, 10, 8),
      );
      expect(inputs.billsDue, 1);
      expect(inputs.billsPaidOnTime, 0);
    });

    test('with no plan, essentials come from what was spent', () {
      final empty = MonthPlan.build(
        month: october,
        recurring: const [],
        items: const [],
        categories: categories,
      );
      final inputs = HealthInputs.forMonth(plan: empty, history: history);
      expect(
        inputs.essentialsMinor,
        kes(25000 + 2000 + 18000 + 3000 + 40 + 11000),
      );
      expect(inputs.billsDue, 0);
      expect(inputs.plannedCategories, 0);
    });

    test('a month with no history is all zeros', () {
      final inputs = HealthInputs.forMonth(plan: plan, history: const []);
      expect(inputs.incomeMinor, 0);
      expect(inputs.spendingMinor, 0);
      expect(inputs.billsDue, 3);
      expect(inputs.billsPaidOnTime, 0);
      expect(inputs.overdraftDays, 0);
      expect(inputs.plannedCategories, 3);
      expect(inputs.categoriesWithinBudget, 3);
    });

    test('ignores other currencies', () {
      final inputs = HealthInputs.forMonth(
        plan: plan,
        history: [
          inflow(at: eat(2026, 10, 5), amount: 100000, currency: 'USD'),
        ],
      );
      expect(inputs.incomeMinor, 0);
    });
  });
}
