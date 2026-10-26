import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/forecast/cash_flow_forecast.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/plan/month_plan.dart';
import 'package:pesaclarity/src/domain/plan/plan_inputs.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

const salary = 1;
const rent = 2;
const food = 3;
const power = 4;
const subscriptions = 5;
const school = 6;

const categories = [
  PlanCategory(id: salary, type: CategoryType.income),
  PlanCategory(id: rent, type: CategoryType.expense),
  PlanCategory(id: food, type: CategoryType.expense, isDailySpending: true),
  PlanCategory(id: power, type: CategoryType.expense),
  PlanCategory(id: subscriptions, type: CategoryType.expense),
  PlanCategory(id: school, type: CategoryType.expense),
];

final october = YearMonth(2026, 10);

/// Monday 12 October 2026.
final monday = CalendarDate(2026, 10, 12);

RecurringBill monthly(
  int id,
  String name,
  int categoryId,
  int shillings,
  int day,
) => RecurringBill(
  id: id,
  name: name,
  categoryId: categoryId,
  amountMinor: kes(shillings),
  frequency: RecurrenceFrequency.monthly,
  startDate: CalendarDate(2026, 1, day),
);

MonthPlan planFor(
  YearMonth month, {
  List<RecurringBill>? recurring,
  List<BudgetItem> items = const [],
}) => MonthPlan.build(
  month: month,
  recurring:
      recurring ??
      [
        monthly(1, 'Salary', salary, 100000, 25),
        monthly(2, 'Rent', rent, 25000, 5),
        monthly(3, 'Food', food, 15000, 1),
        monthly(4, 'KPLC tokens', power, 2000, 20),
        monthly(5, 'Netflix', subscriptions, 1100, 20),
      ],
  items: items,
  categories: categories,
);

LedgerEntry spend(
  CalendarDate date,
  int shillings, {
  int? categoryId = food,
  bool daily = true,
  int fee = 0,
}) => entry(
  at: eat(date.year, date.month, date.day),
  amount: kes(shillings),
  categoryId: categoryId,
  categoryType: categoryId == null ? null : CategoryType.expense,
  isDailySpending: daily,
  fee: fee,
);

/// 1,000 a weekday and 2,000 a weekend day of food from [from] to the day
/// before [to].
List<LedgerEntry> steadySpending(CalendarDate from, CalendarDate to) => [
  for (var d = from; d.isBefore(to); d = d.addDays(1))
    spend(d, d.isWeekend ? 2000 : 1000),
];

final rentPaid = spend(
  CalendarDate(2026, 10, 5),
  25000,
  categoryId: rent,
  daily: false,
);

void main() {
  group('SpendingPace.fromHistory', () {
    test('averages weekdays and weekends over the last four weeks', () {
      final pace = SpendingPace.fromHistory([
        ...steadySpending(monday.addDays(-35), monday),
        spend(monday, 99999),
      ], today: monday);
      expect(pace.weekdayMinor, kes(1000));
      expect(pace.weekendMinor, kes(2000));
      expect(pace.on(CalendarDate(2026, 10, 17)), kes(2000));
    });

    test('is zero with no history', () {
      final pace = SpendingPace.fromHistory(const [], today: monday);
      expect(pace.weekdayMinor, 0);
      expect(pace.weekendMinor, 0);
    });

    test('is zero when history starts today', () {
      final pace = SpendingPace.fromHistory(
        [spend(monday, 500)],
        today: monday,
        historyFrom: monday,
      );
      expect(pace.weekdayMinor, 0);
      expect(pace.weekendMinor, 0);
    });

    test('starts no earlier than the history does', () {
      // Friday to Sunday: one weekday, two weekend days.
      final pace = SpendingPace.fromHistory(
        steadySpending(CalendarDate(2026, 10, 9), monday),
        today: monday,
        historyFrom: CalendarDate(2026, 10, 9),
      );
      expect(pace.weekdayMinor, kes(1000));
      expect(pace.weekendMinor, kes(2000));
    });

    test('uses the overall average when the window has no weekend', () {
      final friday = CalendarDate(2026, 10, 16);
      final pace = SpendingPace.fromHistory(
        [spend(monday, 4000)],
        today: friday,
        historyFrom: monday,
      );
      expect(pace.weekdayMinor, kes(1000));
      expect(pace.weekendMinor, kes(1000));
    });

    test('leaves out scheduled categories but keeps their fees', () {
      final pace = SpendingPace.fromHistory(
        [
          spend(
            CalendarDate(2026, 10, 5),
            28000,
            categoryId: rent,
            daily: false,
            fee: kes(56),
          ),
          spend(CalendarDate(2026, 10, 6), 28000, categoryId: null),
          entry(
            at: eat(2026, 10, 7),
            amount: kes(5600),
            kind: TransactionKind.charge,
          ),
          inflow(
            at: eat(2026, 10, 8),
            amount: kes(2800),
            kind: TransactionKind.reversal,
            categoryId: food,
            categoryType: CategoryType.expense,
          ),
          spend(CalendarDate(2026, 10, 8), 999),
          entry(at: eat(2026, 10, 8), amount: 99900, currency: 'USD'),
        ],
        today: monday,
        scheduledCategoryIds: {rent},
      );
      // 56 + 28,000 + 5,600 - 2,800 + 999, over 20 weekdays.
      expect(pace.weekdayMinor, kes(56 + 28000 + 5600 - 2800 + 999) ~/ 20);
      expect(pace.weekendMinor, 0);
    });

    test('refunds never make the pace negative', () {
      final pace = SpendingPace.fromHistory([
        inflow(
          at: eat(2026, 10, 8),
          amount: kes(2800),
          kind: TransactionKind.reversal,
        ),
      ], today: monday);
      expect(pace.weekdayMinor, 0);
    });
  });

  group('scheduledFlows', () {
    test('lists unpaid bills and income still due, in date order', () {
      final flows = scheduledFlows(planFor(october), [rentPaid], today: monday);
      expect(
        [
          for (final f in flows)
            (f.name, f.date.day, f.amountMinor ~/ 100, f.isIncome),
        ],
        [
          ('KPLC tokens', 20, 2000, false),
          ('Netflix', 20, 1100, false),
          ('Salary', 25, 100000, true),
        ],
      );
    });

    test('moves overdue bills to today and undated items to month end', () {
      final flows = scheduledFlows(
        planFor(
          october,
          items: [
            BudgetItem(
              month: october,
              name: 'School trip',
              categoryId: school,
              amountMinor: kes(3500),
              kind: BudgetItemKind.oneOff,
            ),
          ],
        ),
        [spend(CalendarDate(2026, 10, 4), 20000, categoryId: rent)],
        today: monday,
      );
      final rentFlow = flows.singleWhere((f) => f.name == 'Rent');
      expect(rentFlow.date, monday);
      expect(rentFlow.amountMinor, kes(5000));
      final trip = flows.singleWhere((f) => f.name == 'School trip');
      expect(trip.date, october.lastDay);
    });

    test('counts only income not yet received', () {
      final plan = planFor(
        october,
        recurring: [
          monthly(1, 'Salary', salary, 100000, 25),
          RecurringBill(
            id: 2,
            name: 'Side gig',
            categoryId: salary,
            amountMinor: kes(10000),
            frequency: RecurrenceFrequency.weekly,
            startDate: CalendarDate(2026, 10, 2),
          ),
        ],
      );
      final flows = scheduledFlows(plan, [
        inflow(
          at: eat(2026, 10, 2),
          amount: kes(10000),
          categoryId: salary,
          categoryType: CategoryType.income,
        ),
        inflow(
          at: eat(2026, 10, 9),
          amount: kes(4000),
          categoryId: salary,
          categoryType: CategoryType.income,
        ),
      ], today: monday);
      // The 9 October gig is late and part paid, so it is left out.
      expect(
        [for (final f in flows) (f.date.day, f.amountMinor ~/ 100)],
        [(16, 10000), (23, 10000), (25, 100000), (30, 10000)],
      );
    });
  });

  group('CashFlowForecast.project', () {
    CashFlowForecast forecast({
      required int balance,
      CalendarDate? today,
      MonthPlan? plan,
      List<LedgerEntry>? entries,
      CalendarDate? historyFrom,
    }) {
      final day = today ?? monday;
      return CashFlowForecast.project(
        balanceMinor: kes(balance),
        today: day,
        plan: plan ?? planFor(day.yearMonth),
        entries:
            entries ?? [...steadySpending(day.addDays(-28), day), rentPaid],
        historyFrom: historyFrom,
      );
    }

    test('finds the zero date and the charge that would fail', () {
      final result = forecast(balance: 12000);
      expect(result.days.first.date, monday);
      expect(result.days.last.date, CalendarDate(2026, 10, 31));
      expect(result.days, hasLength(20));
      expect(result.zeroDate, CalendarDate(2026, 10, 20));

      final failing = result.failingCharges.single;
      expect(failing.name, 'Netflix');
      expect(failing.date, CalendarDate(2026, 10, 20));
      expect(failing.balanceBeforeMinor, 0);
      expect(failing.shortMinor, kes(1100));

      final payday = result.days.singleWhere((d) => d.date.day == 25);
      expect(payday.incomeMinor, kes(100000));
      expect(result.monthEndBalanceMinor, kes(83900));

      expect(result.messages, [
        'At this pace you hit zero on the 20th.',
        'Your Netflix payment of KES 1,100 on the 20th may not go through. '
            'You would be KES 1,100 short.',
      ]);
    });

    test('runway counts the days until the money runs out', () {
      final result = forecast(balance: 12000);
      expect(result.runwayDays, 8);
      expect(result.nextIncome?.name, 'Salary');
      expect(result.nextIncome?.date, CalendarDate(2026, 10, 25));
    });

    test('runway past month end spreads what is left at the pace', () {
      // KES 121,900 left at 9,000 a week, after the 20 days to month end.
      expect(forecast(balance: 50000).runwayDays, 20 + 94);
    });

    test('runway is unknown when nothing is being spent', () {
      final result = forecast(balance: 1000000, entries: const []);
      expect(result.zeroDate, isNull);
      expect(result.runwayDays, isNull);
    });

    test('says what is left at month end when the money lasts', () {
      final result = forecast(balance: 50000);
      expect(result.zeroDate, isNull);
      expect(result.failingCharges, isEmpty);
      expect(result.messages, [
        'At this pace you end the month with KES 121,900.',
      ]);
    });

    test('counts what was already spent today against today\'s pace', () {
      final result = forecast(
        balance: 50000,
        entries: [
          ...steadySpending(monday.addDays(-28), monday),
          rentPaid,
          spend(monday, 600),
        ],
      );
      expect(result.days.first.spendingMinor, kes(400));

      final overspent = forecast(
        balance: 50000,
        entries: [
          ...steadySpending(monday.addDays(-28), monday),
          rentPaid,
          spend(monday, 1500),
        ],
      );
      expect(overspent.days.first.spendingMinor, 0);
    });

    test('with no history and no income, only bills move the balance', () {
      final result = forecast(
        balance: 2500,
        entries: const [],
        historyFrom: monday,
        plan: planFor(
          october,
          recurring: [
            monthly(4, 'KPLC tokens', power, 2000, 20),
            monthly(5, 'Netflix', subscriptions, 1100, 20),
          ],
        ),
      );
      expect(result.pace.weekdayMinor, 0);
      expect(result.zeroDate, CalendarDate(2026, 10, 20));
      expect(result.failingCharges.single.shortMinor, kes(600));
      expect(result.monthEndBalanceMinor, kes(-600));
    });

    test('an empty balance hits zero today', () {
      final result = forecast(
        balance: 0,
        entries: const [],
        plan: planFor(october, recurring: const []),
      );
      expect(result.zeroDate, monday);
      expect(result.messages.first, 'At this pace you hit zero today.');
    });

    test('an overdue bill fails today', () {
      final result = forecast(
        balance: 3000,
        entries: steadySpending(monday.addDays(-28), monday),
      );
      final failing = result.failingCharges.first;
      expect(failing.name, 'Rent');
      expect(failing.date, monday);
      expect(
        result.messages[1],
        'Your Rent payment of KES 25,000 today may not go through. '
        'You would be KES 22,000 short.',
      );
    });

    test('on the last day of the month it forecasts one day', () {
      final last = CalendarDate(2026, 10, 31);
      final result = forecast(balance: 5000, today: last);
      expect(result.days, hasLength(1));
      expect(result.days.single.spendingMinor, kes(2000)); // Saturday.
    });

    test('on the first of the month the pace reaches into last month', () {
      final first = CalendarDate(2026, 11, 1);
      final result = forecast(
        balance: 200000,
        today: first,
        entries: steadySpending(first.addDays(-28), first),
        plan: planFor(YearMonth(2026, 11), recurring: const []),
      );
      expect(result.pace.weekdayMinor, kes(1000));
      expect(result.days, hasLength(30));
    });

    test('refuses a plan for another month', () {
      expect(
        () => forecast(balance: 1000, plan: planFor(YearMonth(2026, 11))),
        throwsArgumentError,
      );
    });
  });

  test('ordinalDay', () {
    expect([1, 2, 3, 4, 11, 12, 13, 20, 21, 22, 23, 30, 31].map(ordinalDay), [
      '1st',
      '2nd',
      '3rd',
      '4th',
      '11th',
      '12th',
      '13th',
      '20th',
      '21st',
      '22nd',
      '23rd',
      '30th',
      '31st',
    ]);
  });
}
