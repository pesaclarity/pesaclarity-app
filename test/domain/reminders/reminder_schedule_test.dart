import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/plan/month_plan.dart';
import 'package:pesaclarity/src/domain/plan/plan_inputs.dart';
import 'package:pesaclarity/src/domain/reminders/recurring_charges.dart';
import 'package:pesaclarity/src/domain/reminders/reminder_schedule.dart';
import 'package:pesaclarity/src/domain/reminders/reminder_settings.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  const on = ReminderSettings(enabled: true);
  // Monday 26 October 2026, 07:00 in Nairobi.
  final now = eat(2026, 10, 26, 7);

  DuePayment bill(String name, int shillings, CalendarDate due) =>
      DuePayment(name: name, amountMinor: kes(shillings), dueDate: due);

  group('planReminders', () {
    test('schedules nothing while reminders are off', () {
      final reminders = planReminders(
        settings: const ReminderSettings(),
        now: now,
        bills: [bill('Rent', 25000, CalendarDate(2026, 11, 1))],
      );
      expect(reminders, isEmpty);
    });

    test('reminds about a bill the lead time before, at 9:00', () {
      final reminders = planReminders(
        settings: on.copyWith(leadDays: 2),
        now: now,
        bills: [bill('Rent', 25000, CalendarDate(2026, 11, 1))],
      );
      expect(reminders, hasLength(1));
      final rent = reminders.single;
      expect(rent.kind, ReminderKind.bill);
      expect(rent.at, eat(2026, 10, 30, 9));
      expect(rent.title, 'Rent is due in 2 days');
      expect(rent.body, 'Pay KES 25,000 by Sun 1 Nov.');
    });

    test('moves a late reminder to the next 9:00 up to the due date', () {
      final at10 = eat(2026, 10, 26, 10);
      final reminders = planReminders(
        settings: on.copyWith(leadDays: 3),
        now: at10,
        bills: [
          bill('School fees', 30000, CalendarDate(2026, 10, 28)),
          bill('Water', 800, CalendarDate(2026, 10, 26)),
        ],
      );
      expect(reminders.map((r) => r.title), ['School fees is due tomorrow']);
      expect(reminders.single.at, eat(2026, 10, 27, 9));
    });

    test('keeps amounts out of every notification when asked', () {
      final reminders = planReminders(
        settings: on.copyWith(dailySafeToSpend: true),
        now: now,
        showAmounts: false,
        bills: [bill('Rent', 25000, CalendarDate(2026, 11, 1))],
        charges: [
          RecurringCharge(
            name: 'Example Stream',
            amountMinor: kes(1100),
            lastDate: CalendarDate(2026, 10, 3),
            nextDate: CalendarDate(2026, 11, 3),
          ),
        ],
        safeToSpendTodayMinor: kes(1240),
      );
      expect(reminders, isNotEmpty);
      for (final r in reminders) {
        expect('${r.title} ${r.body}', isNot(contains('KES')), reason: '$r');
      }
    });

    test('reminds about card charges and paydays', () {
      final reminders = planReminders(
        settings: on,
        now: now,
        charges: [
          RecurringCharge(
            name: 'Example Stream',
            amountMinor: kes(1100),
            lastDate: CalendarDate(2026, 10, 3),
            nextDate: CalendarDate(2026, 11, 3),
          ),
        ],
        paydays: [bill('Salary', 80000, CalendarDate(2026, 10, 30))],
      );
      expect(reminders.map((r) => (r.kind, r.at, r.title)), [
        (ReminderKind.payday, eat(2026, 10, 30, 9), 'Payday: Salary'),
        (
          ReminderKind.cardCharge,
          eat(2026, 11, 2, 9),
          'Example Stream charges tomorrow',
        ),
      ]);
      expect(reminders.last.body, contains('KES 1,100'));
      expect(reminders.map((r) => r.id), [1, 2]);
    });

    test('respects each switch', () {
      final reminders = planReminders(
        settings: on.copyWith(bills: false, payday: false),
        now: now,
        bills: [bill('Rent', 25000, CalendarDate(2026, 11, 1))],
        paydays: [bill('Salary', 80000, CalendarDate(2026, 10, 30))],
      );
      expect(reminders, isEmpty);
    });

    test('shows safe-to-spend daily, with the amount only today', () {
      final reminders = planReminders(
        settings: on.copyWith(dailySafeToSpend: true, dailyMinuteOfDay: 8 * 60),
        now: now,
        safeToSpendTodayMinor: kes(1240),
        dailyDays: 3,
      );
      expect(reminders.map((r) => r.at), [
        eat(2026, 10, 26, 8),
        eat(2026, 10, 27, 8),
        eat(2026, 10, 28, 8),
      ]);
      expect(reminders.first.body, 'KES 1,240 for today.');
      expect(reminders[1].body, 'See what you can spend today.');
    });

    test('skips today once the daily time has passed', () {
      final reminders = planReminders(
        settings: on.copyWith(dailySafeToSpend: true, dailyMinuteOfDay: 6 * 60),
        now: now,
        safeToSpendTodayMinor: kes(1240),
        dailyDays: 2,
      );
      expect(reminders.single.at, eat(2026, 10, 27, 6));
      expect(reminders.single.body, 'See what you can spend today.');
    });
  });

  group('duePaymentsIn', () {
    test('lists unpaid bills and paydays, not budgets or paid bills', () {
      const rent = 1;
      const food = 2;
      const salary = 3;
      const internet = 4;
      final month = YearMonth(2026, 10);
      RecurringBill recurring(int id, String name, int category, int day) =>
          RecurringBill(
            id: id,
            name: name,
            categoryId: category,
            amountMinor: kes(1000),
            frequency: RecurrenceFrequency.monthly,
            startDate: CalendarDate(2026, 1, day),
          );
      final plan = MonthPlan.build(
        month: month,
        categories: const [
          PlanCategory(id: rent, type: CategoryType.expense),
          PlanCategory(
            id: food,
            type: CategoryType.expense,
            isDailySpending: true,
          ),
          PlanCategory(id: salary, type: CategoryType.income),
          PlanCategory(id: internet, type: CategoryType.expense),
        ],
        recurring: [
          recurring(1, 'Rent', rent, 28),
          recurring(2, 'Food', food, 1),
          recurring(3, 'Salary', salary, 30),
          recurring(4, 'Internet', internet, 29),
        ],
        items: const [],
      );
      final review = MonthReview.of(plan, [
        entry(
          at: eat(2026, 10, 20),
          amount: kes(1000),
          categoryId: internet,
          categoryType: CategoryType.expense,
        ),
      ]);

      final due = duePaymentsIn(review);
      expect(due.bills.map((b) => (b.name, b.dueDate)), [
        ('Rent', CalendarDate(2026, 10, 28)),
      ]);
      expect(due.paydays.map((p) => p.name), ['Salary']);
    });
  });

  group('ReminderSettings', () {
    test('round-trips through JSON and falls back on bad values', () {
      const settings = ReminderSettings(
        enabled: true,
        cardCharges: false,
        dailySafeToSpend: true,
        dailyMinuteOfDay: 19 * 60 + 30,
        leadDays: 3,
      );
      expect(ReminderSettings.fromJson(settings.toJson()), settings);
      expect(
        ReminderSettings.fromJson({'leadDays': -4, 'dailyMinuteOfDay': 5000}),
        const ReminderSettings(),
      );
    });

    test('labels lead times', () {
      expect(ReminderSettings.leadDayChoices.map(leadDaysLabel), [
        'On the day',
        '1 day before',
        '2 days before',
        '3 days before',
        '1 week before',
      ]);
    });
  });
}
