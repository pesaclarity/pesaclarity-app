import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
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
const school = 7;

const categories = [
  PlanCategory(id: salary, type: CategoryType.income),
  PlanCategory(id: rent, type: CategoryType.expense),
  PlanCategory(id: food, type: CategoryType.expense, isDailySpending: true),
  PlanCategory(id: power, type: CategoryType.expense),
  PlanCategory(id: loan, type: CategoryType.debt),
  PlanCategory(id: savings, type: CategoryType.savings),
  PlanCategory(id: school, type: CategoryType.expense),
];

final october = YearMonth(2026, 10);

RecurringBill monthly(int id, int categoryId, int shillings, {int day = 1}) =>
    RecurringBill(
      id: id,
      name: 'Bill $id',
      categoryId: categoryId,
      amountMinor: kes(shillings),
      frequency: RecurrenceFrequency.monthly,
      startDate: CalendarDate(2026, 1, day),
    );

final recurring = [
  monthly(1, salary, 120000, day: 25),
  monthly(2, rent, 25000, day: 5),
  monthly(3, food, 15000),
  monthly(4, power, 2000, day: 20),
  monthly(5, loan, 10000, day: 10),
  monthly(6, savings, 8000, day: 26),
];

MonthPlan octoberPlan([List<BudgetItem> items = const []]) => MonthPlan.build(
  month: october,
  recurring: recurring,
  items: items,
  categories: categories,
);

LedgerEntry paid(
  int categoryId,
  int shillings, {
  DateTime? at,
  CategoryType type = CategoryType.expense,
  bool daily = false,
}) => entry(
  at: at ?? eat(2026, 10, 15),
  amount: kes(shillings),
  categoryId: categoryId,
  categoryType: type,
  isDailySpending: daily,
);

CategoryProgress progressOf(MonthReview review, int? categoryId) =>
    review.categories.singleWhere((c) => c.categoryId == categoryId);

void main() {
  group('MonthPlan.build', () {
    test(
      'combines recurring lines with this month\'s one-offs and arrears',
      () {
        final plan = octoberPlan([
          BudgetItem(
            id: 1,
            month: october,
            name: 'School trip',
            categoryId: school,
            amountMinor: kes(3500),
            kind: BudgetItemKind.oneOff,
          ),
          BudgetItem(
            id: 2,
            month: october,
            name: 'Rent',
            categoryId: rent,
            amountMinor: kes(5000),
            kind: BudgetItemKind.carriedArrears,
          ),
          BudgetItem(
            id: 3,
            month: october.next,
            name: 'Not this month',
            amountMinor: kes(999),
            kind: BudgetItemKind.oneOff,
          ),
        ]);

        expect(plan.lines, hasLength(8));
        expect(
          plan.lines.map((l) => l.source).toSet(),
          PlanLineSource.values.toSet(),
        );
        expect(plan.expectedIncomeMinor, kes(120000));
        expect(
          plan.plannedOutgoingMinor,
          kes(25000 + 15000 + 2000 + 10000 + 8000 + 3500 + 5000),
        );
        expect(plan.dayToDayBudgetMinor, kes(15000));
        expect(plan.plannedByType, {
          CategoryType.expense: kes(25000 + 15000 + 2000 + 3500 + 5000),
          CategoryType.debt: kes(10000),
          CategoryType.savings: kes(8000),
        });
        final rentLine = plan.lines.firstWhere(
          (l) => l.sourceId == 2 && l.source == PlanLineSource.recurring,
        );
        expect(rentLine.dueDate, CalendarDate(2026, 10, 5));
      },
    );

    test('an empty plan is all zeros', () {
      final plan = MonthPlan.build(
        month: october,
        recurring: const [],
        items: const [],
        categories: const [],
      );
      expect(plan.lines, isEmpty);
      expect(plan.expectedIncomeMinor, 0);
      expect(plan.plannedOutgoingMinor, 0);
      expect(MonthReview.of(plan, const []).categories, isEmpty);
    });
  });

  group('MonthReview', () {
    test('labels each category Done, In progress or Over', () {
      final review = MonthReview.of(octoberPlan(), [
        paid(rent, 25000),
        paid(food, 9000, daily: true),
        paid(power, 2300),
      ]);

      expect(progressOf(review, rent).status, PlanStatus.done);
      expect(progressOf(review, food).status, PlanStatus.inProgress);
      expect(progressOf(review, food).leftMinor, kes(6000));
      expect(progressOf(review, power).status, PlanStatus.over);
      expect(progressOf(review, loan).status, PlanStatus.inProgress);
      expect(PlanStatus.values.map((s) => s.label), [
        'Done',
        'In progress',
        'Over',
      ]);
    });

    test('counts debt payments and savings against their categories', () {
      final review = MonthReview.of(octoberPlan(), [
        paid(loan, 10000, type: CategoryType.debt),
        paid(savings, 8000, type: CategoryType.savings),
      ]);
      expect(progressOf(review, loan).status, PlanStatus.done);
      expect(progressOf(review, savings).status, PlanStatus.done);
    });

    test('shows unplanned spending as Over, including Uncategorised', () {
      final review = MonthReview.of(octoberPlan(), [
        paid(school, 1200),
        entry(at: eat(2026, 10, 3), amount: kes(450)),
      ]);
      expect(progressOf(review, school).status, PlanStatus.over);
      final uncategorised = progressOf(review, null);
      expect(uncategorised.actualMinor, kes(450));
      expect(uncategorised.status, PlanStatus.over);
      expect(review.categories.last.categoryId, isNull);
    });

    test('a one-off marked paid is Done without a matching transaction', () {
      final review = MonthReview.of(
        octoberPlan([
          BudgetItem(
            id: 1,
            month: october,
            name: 'Uniform',
            categoryId: school,
            amountMinor: kes(4000),
            kind: BudgetItemKind.oneOff,
            isPaid: true,
          ),
        ]),
        const [],
      );
      expect(progressOf(review, school).status, PlanStatus.done);
      expect(
        review.arrearsToCarry.where((a) => a.categoryId == school),
        isEmpty,
      );
    });

    test(
      'only counts this Nairobi month, net of refunds, without transfers',
      () {
        final review = MonthReview.of(octoberPlan(), [
          paid(food, 1000, daily: true, at: eat(2026, 10, 1, 0)),
          paid(food, 1000, daily: true, at: eat(2026, 9, 30, 23, 59)),
          paid(food, 1000, daily: true, at: eat(2026, 11, 1, 0)),
          inflow(
            kind: TransactionKind.reversal,
            at: eat(2026, 10, 2),
            amount: kes(200),
            categoryId: food,
            categoryType: CategoryType.expense,
          ),
          entry(
            at: eat(2026, 10, 3),
            amount: kes(5000),
            categoryId: food,
            transferPairId: 99,
          ),
          entry(
            kind: TransactionKind.fulizaRepayment,
            at: eat(2026, 10, 4),
            amount: kes(505),
          ),
          entry(
            at: eat(2026, 10, 4),
            amount: 5000,
            categoryId: food,
            isDailySpending: true,
            currency: 'USD',
          ),
        ]);
        expect(progressOf(review, food).actualMinor, kes(800));
        expect(review.categories.where((c) => c.categoryId == null), isEmpty);
      },
    );
  });

  group('arrears', () {
    test('pays arrears first and carries the unpaid part forward', () {
      final review = MonthReview.of(
        octoberPlan([
          BudgetItem(
            id: 9,
            month: october,
            name: 'Rent',
            categoryId: rent,
            amountMinor: kes(5000),
            kind: BudgetItemKind.carriedArrears,
          ),
        ]),
        [paid(rent, 20000)],
      );
      final rentProgress = progressOf(review, rent);
      expect(rentProgress.lines.first.line.source, PlanLineSource.arrears);
      expect(rentProgress.lines.first.isPaid, isTrue);
      expect(rentProgress.status, PlanStatus.inProgress);

      final carried = review.arrearsToCarry.singleWhere(
        (a) => a.categoryId == rent,
      );
      expect(carried.month, YearMonth(2026, 11));
      expect(carried.kind, BudgetItemKind.carriedArrears);
      expect(carried.amountMinor, kes(10000));
      expect(carried.name, 'Bill 2');
    });

    test(
      'carries bills, debts and uncategorised lines, not budgets or savings',
      () {
        final review = MonthReview.of(
          octoberPlan([
            BudgetItem(
              month: october,
              name: 'Uncategorised bill',
              amountMinor: kes(700),
              kind: BudgetItemKind.oneOff,
            ),
          ]),
          [paid(rent, 25000), paid(power, 500)],
        );
        final carried = {
          for (final a in review.arrearsToCarry) a.categoryId: a.amountMinor,
        };
        expect(carried, {power: kes(1500), loan: kes(10000), null: kes(700)});
      },
    );

    test('carries December arrears into January', () {
      final december = MonthReview.of(
        MonthPlan.build(
          month: YearMonth(2026, 12),
          recurring: recurring,
          items: const [],
          categories: categories,
        ),
        const [],
      );
      expect(december.arrearsToCarry.map((a) => a.month).toSet(), {
        YearMonth(2027, 1),
      });
    });

    test('arrears appear in the next month\'s plan', () {
      final carried = MonthReview.of(octoberPlan(), [
        paid(rent, 25000),
        paid(power, 2000),
      ]).arrearsToCarry;
      final november = MonthPlan.build(
        month: october.next,
        recurring: recurring,
        items: carried,
        categories: categories,
      );
      final arrears = november.lines.where(
        (l) => l.source == PlanLineSource.arrears,
      );
      expect(arrears.map((l) => l.amountMinor), [kes(10000)]);
      expect(
        november.plannedOutgoingMinor,
        octoberPlan().plannedOutgoingMinor + kes(10000),
      );
    });
  });
}
