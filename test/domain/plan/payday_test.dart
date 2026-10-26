import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/debts/debt.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/plan/month_plan.dart';
import 'package:pesaclarity/src/domain/plan/payday.dart';
import 'package:pesaclarity/src/domain/plan/plan_groups.dart';
import 'package:pesaclarity/src/domain/plan/plan_inputs.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

const salary = 1;
const rent = 2;
const food = 3;
const loan = 4;
const savings = 5;
const tax = 6;
const school = 7;

const categories = [
  PlanCategory(id: salary, type: CategoryType.income, key: 'salary'),
  PlanCategory(id: rent, type: CategoryType.expense, key: 'rent'),
  PlanCategory(id: food, type: CategoryType.expense, isDailySpending: true),
  PlanCategory(id: loan, type: CategoryType.debt),
  PlanCategory(id: savings, type: CategoryType.savings),
  PlanCategory(id: tax, type: CategoryType.tax),
  PlanCategory(id: school, type: CategoryType.expense, key: 'school_fees'),
];

final november = YearMonth(2026, 11);

RecurringBill monthly(
  int id,
  String name,
  int categoryId,
  int shillings, {
  int day = 1,
}) => RecurringBill(
  id: id,
  name: name,
  categoryId: categoryId,
  amountMinor: kes(shillings),
  frequency: RecurrenceFrequency.monthly,
  startDate: CalendarDate(2026, 1, day),
);

MonthPlan novemberPlan({List<RecurringBill>? recurring}) => MonthPlan.build(
  month: november,
  recurring:
      recurring ??
      [
        monthly(1, 'Salary', salary, 100000, day: 25),
        monthly(2, 'Rent', rent, 25000, day: 5),
        monthly(3, 'Food', food, 15000),
        monthly(4, 'Loan', loan, 10000, day: 10),
        monthly(5, 'Savings', savings, 5000, day: 26),
        monthly(6, 'Tax reserve', tax, 8000, day: 26),
        monthly(7, 'School fees', school, 12000, day: 2),
      ],
  items: const [],
  categories: categories,
);

void main() {
  group('plannedGroups', () {
    test('groups outgoings as debt, tax, living, school and savings', () {
      final groups = {
        for (final g in plannedGroups(novemberPlan())) g.group: g.amountMinor,
      };
      expect(groups, {
        PlanGroup.debt: kes(10000),
        PlanGroup.tax: kes(8000),
        PlanGroup.living: kes(40000),
        PlanGroup.school: kes(12000),
        PlanGroup.savings: kes(5000),
      });
    });
  });

  group('detectPayday', () {
    final plan = novemberPlan();

    test('finds salary that landed in the last week', () {
      final payday = detectPayday(
        plan: plan,
        entries: [
          inflow(
            at: eat(2026, 11, 24, 9),
            amount: kes(98000),
            categoryId: salary,
            categoryType: CategoryType.income,
            payeeId: 1,
          ),
        ],
        today: CalendarDate(2026, 11, 26),
      );
      expect(payday, isNotNull);
      expect(payday!.fromMessage, isTrue);
      expect(payday.amountMinor, kes(98000));
      expect(payday.date, CalendarDate(2026, 11, 24));
    });

    test('counts a large uncategorised income as salary', () {
      final payday = detectPayday(
        plan: plan,
        entries: [
          inflow(
            at: eat(2026, 11, 25),
            amount: kes(60000),
            kind: TransactionKind.bank,
          ),
        ],
        today: CalendarDate(2026, 11, 25),
      );
      expect(payday?.amountMinor, kes(60000));
    });

    test('ignores small income and money from unnamed people', () {
      final payday = detectPayday(
        plan: plan,
        entries: [
          inflow(at: eat(2026, 11, 20), amount: kes(2000), payeeId: 9),
          inflow(at: eat(2026, 11, 20), amount: kes(90000)),
        ],
        today: CalendarDate(2026, 11, 21),
      );
      expect(payday, isNull);
    });

    test('falls back to the planned salary date', () {
      final payday = detectPayday(
        plan: plan,
        entries: const [],
        today: CalendarDate(2026, 11, 27),
      );
      expect(payday?.fromMessage, isFalse);
      expect(payday?.date, CalendarDate(2026, 11, 25));
      expect(payday?.amountMinor, kes(100000));
    });

    test('stops offering a week after payday', () {
      expect(
        detectPayday(
          plan: plan,
          entries: const [],
          today: CalendarDate(2026, 11, 20),
        ),
        isNull,
      );
      expect(
        detectPayday(
          plan: plan,
          entries: [
            inflow(
              at: eat(2026, 11, 2),
              amount: kes(100000),
              categoryId: salary,
              categoryType: CategoryType.income,
              payeeId: 1,
            ),
          ],
          today: CalendarDate(2026, 11, 20),
        ),
        isNull,
      );
    });
  });

  group('PaydayChecklist.propose', () {
    test('lists bills, debts, set-asides and savings in that order', () {
      final review = MonthReview.of(novemberPlan(), const []);
      final checklist = PaydayChecklist.propose(
        review: review,
        incomeMinor: kes(100000),
      );

      expect(
        [for (final t in checklist.tasks) (t.kind, t.name, t.amountMinor)],
        [
          (PaydayTaskKind.bill, 'School fees', kes(12000)),
          (PaydayTaskKind.bill, 'Rent', kes(25000)),
          (PaydayTaskKind.debt, 'Loan', kes(10000)),
          // Surplus 25,000: half to debt, half to savings.
          (PaydayTaskKind.debt, 'Extra to debt', kes(12500)),
          (PaydayTaskKind.setAside, 'Tax reserve', kes(8000)),
          (PaydayTaskKind.setAside, 'Day-to-day spending', kes(15000)),
          (PaydayTaskKind.savings, 'Savings', kes(5000)),
          (PaydayTaskKind.savings, 'Surplus to savings', kes(12500)),
        ],
      );
      expect(checklist.plannedMinor, kes(100000));
      expect(checklist.shortfallMinor, 0);
    });

    test('leaves out what is already paid', () {
      final review = MonthReview.of(novemberPlan(), [
        entry(
          at: eat(2026, 11, 5),
          amount: kes(25000),
          categoryId: rent,
          categoryType: CategoryType.expense,
        ),
      ]);
      final checklist = PaydayChecklist.propose(
        review: review,
        incomeMinor: kes(100000),
      );
      expect(checklist.tasks.map((t) => t.name), isNot(contains('Rent')));
    });

    test('splits debt money across debts with the payday split', () {
      final review = MonthReview.of(novemberPlan(), const []);
      final checklist = PaydayChecklist.propose(
        review: review,
        incomeMinor: kes(100000),
        debtShareBasisPoints: 10000,
        debts: [
          Debt(
            id: 1,
            lender: 'KCB loan',
            type: DebtType.bankLoan,
            balanceMinor: kes(200000),
            annualRateBasisPoints: 1400,
            minimumPaymentMinor: kes(6000),
          ),
          Debt(
            id: 2,
            lender: 'Card',
            type: DebtType.card,
            balanceMinor: kes(50000),
            annualRateBasisPoints: 3600,
            minimumPaymentMinor: kes(4000),
          ),
        ],
      );
      final debts = {
        for (final t in checklist.tasks)
          if (t.kind == PaydayTaskKind.debt) t.name: t.amountMinor,
      };
      // Planned 10,000 covers both minimums; the whole 25,000 surplus goes
      // to the dearest debt.
      expect(debts, {'Card': kes(29000), 'KCB loan': kes(6000)});
      expect(checklist.tasks.where((t) => t.key == 'surplus:savings'), isEmpty);
    });

    test('shows the shortfall when income does not cover the plan', () {
      final review = MonthReview.of(novemberPlan(), const []);
      final checklist = PaydayChecklist.propose(
        review: review,
        incomeMinor: kes(60000),
      );
      expect(checklist.shortfallMinor, kes(15000));
      expect(
        checklist.tasks.map((t) => t.key),
        isNot(contains('surplus:debt')),
      );
    });

    test('is complete when every task is ticked', () {
      final checklist = PaydayChecklist.propose(
        review: MonthReview.of(novemberPlan(), const []),
        incomeMinor: kes(100000),
      );
      final keys = {for (final t in checklist.tasks) t.key};
      expect(checklist.isComplete(keys), isTrue);
      expect(checklist.isComplete(keys.skip(1).toSet()), isFalse);
    });
  });
}
