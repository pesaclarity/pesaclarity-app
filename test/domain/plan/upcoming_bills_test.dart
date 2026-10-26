import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/plan/month_plan.dart';
import 'package:pesaclarity/src/domain/plan/plan_inputs.dart';
import 'package:pesaclarity/src/domain/plan/upcoming_bills.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

const salary = 1;
const rent = 2;
const food = 3;
const power = 4;

const categories = [
  PlanCategory(id: salary, type: CategoryType.income),
  PlanCategory(id: rent, type: CategoryType.expense),
  PlanCategory(id: food, type: CategoryType.expense, isDailySpending: true),
  PlanCategory(id: power, type: CategoryType.expense),
];

RecurringBill monthly(
  int id,
  String name,
  int category,
  int kesAmount,
  int day,
) => RecurringBill(
  id: id,
  name: name,
  categoryId: category,
  amountMinor: kes(kesAmount),
  frequency: RecurrenceFrequency.monthly,
  startDate: CalendarDate(2026, 1, day),
);

final recurring = [
  monthly(1, 'Salary', salary, 100000, 25),
  monthly(2, 'Rent', rent, 15000, 5),
  monthly(3, 'Food', food, 12000, 1),
  monthly(4, 'KPLC tokens', power, 2000, 28),
  monthly(5, 'Water', power, 800, 22),
];

MonthPlan planFor(YearMonth month, {List<BudgetItem> items = const []}) =>
    MonthPlan.build(
      month: month,
      recurring: recurring,
      items: items,
      categories: categories,
    );

void main() {
  // Monday 26 October 2026.
  final today = CalendarDate(2026, 10, 26);
  final october = YearMonth(2026, 10);

  test('lists unpaid bills in the next two weeks, overdue first', () {
    final bills = upcomingBills(
      thisMonth: planFor(
        october,
        items: [
          BudgetItem(
            month: october,
            name: 'Wedding contribution',
            amountMinor: kes(3000),
            kind: BudgetItemKind.oneOff,
          ),
        ],
      ),
      nextMonth: planFor(october.next),
      entries: const [],
      today: today,
    );

    expect(bills.map((b) => b.name), [
      'Rent', // 5 Oct, overdue
      'Water', // 22 Oct, overdue
      'KPLC tokens', // 28 Oct
      'Rent', // 5 Nov
      'Wedding contribution', // any time this month
    ]);
    expect(bills.first.isOverdueOn(today), isTrue);
    expect(bills[3].dueDate, CalendarDate(2026, 11, 5));
    expect(bills.last.dueDate, isNull);
  });

  test('leaves out paid bills, day-to-day budgets and income', () {
    final bills = upcomingBills(
      thisMonth: planFor(october),
      entries: [
        entry(
          at: eat(2026, 10, 5),
          amount: kes(15000),
          categoryId: rent,
          categoryType: CategoryType.expense,
        ),
        entry(
          at: eat(2026, 10, 22),
          amount: kes(500),
          categoryId: power,
          categoryType: CategoryType.expense,
        ),
      ],
      today: today,
    );

    // 500 of power paid goes to Water, the earlier line.
    expect(bills.map((b) => (b.name, b.amountMinor)), [
      ('Water', kes(300)),
      ('KPLC tokens', kes(2000)),
    ]);
  });

  test('ignores next month beyond the horizon', () {
    final bills = upcomingBills(
      thisMonth: planFor(october),
      nextMonth: planFor(october.next),
      entries: const [],
      today: CalendarDate(2026, 10, 1),
    );
    expect(bills.map((b) => b.name), ['Rent']);
  });
}
