import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/budget/safe_to_spend.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

LedgerEntry food(DateTime at, int amount, {String currency = 'KES'}) => entry(
  at: at,
  amount: amount,
  categoryId: 1,
  categoryType: CategoryType.expense,
  isDailySpending: true,
  currency: currency,
);

void main() {
  // Monday 26 October 2026: Mon to Fri plus Saturday 31st are left.
  final monday = CalendarDate(2026, 10, 26);

  group('SafeToSpend.calculate', () {
    test('splits what is left evenly by default', () {
      final result = SafeToSpend.calculate(
        budgetMinor: kes(30000),
        entries: [food(eat(2026, 10, 10), kes(24000))],
        today: monday,
      );
      expect(result.weekdaysLeft, 5);
      expect(result.weekendDaysLeft, 1);
      expect(result.weekdayLimitMinor, kes(1000));
      expect(result.weekendLimitMinor, kes(1000));
      expect(result.todayLimitMinor, kes(1000));
      expect(result.leftTodayMinor, kes(1000));
      expect(result.leftThisMonthMinor, kes(6000));
    });

    test('weights weekends and never hands out more than is left', () {
      final result = SafeToSpend.calculate(
        budgetMinor: kes(30000),
        entries: [food(eat(2026, 10, 10), kes(24000))],
        today: monday,
        weekendWeightPercent: 200,
      );
      expect(result.weekdayLimitMinor, 85714);
      expect(result.weekendLimitMinor, 171428);
      expect(
        result.weekdayLimitMinor * result.weekdaysLeft +
            result.weekendLimitMinor * result.weekendDaysLeft,
        lessThanOrEqualTo(kes(6000)),
      );
    });

    test('uses the weekend limit on a weekend day', () {
      final result = SafeToSpend.calculate(
        budgetMinor: kes(9000),
        entries: const [],
        today: CalendarDate(2026, 10, 24),
        weekendWeightPercent: 200,
      );
      // Sat 24 to Sat 31: 5 weekdays and 3 weekend days, 11 shares.
      expect(result.weekdaysLeft, 5);
      expect(result.weekendDaysLeft, 3);
      expect(result.todayLimitMinor, result.weekendLimitMinor);
      expect(result.weekendLimitMinor, 163636);
    });

    test('spending today lowers what is left today, not the limits', () {
      final result = SafeToSpend.calculate(
        budgetMinor: kes(30000),
        entries: [
          food(eat(2026, 10, 10), kes(24000)),
          food(eat(2026, 10, 26, 8), kes(400)),
        ],
        today: monday,
      );
      expect(result.spentTodayMinor, kes(400));
      expect(result.todayLimitMinor, kes(1000));
      expect(result.leftTodayMinor, kes(600));
      expect(result.overTodayMinor, 0);
      expect(result.leftThisMonthMinor, kes(5600));
    });

    test('reports going over today without a negative limit', () {
      final result = SafeToSpend.calculate(
        budgetMinor: kes(30000),
        entries: [
          food(eat(2026, 10, 10), kes(24000)),
          food(eat(2026, 10, 26, 8), kes(1500)),
        ],
        today: monday,
      );
      expect(result.leftTodayMinor, 0);
      expect(result.overTodayMinor, kes(500));
    });

    test('gives zero limits once the budget is used up', () {
      final result = SafeToSpend.calculate(
        budgetMinor: kes(10000),
        entries: [
          food(eat(2026, 10, 10), kes(12000)),
          food(eat(2026, 10, 26), kes(200)),
        ],
        today: monday,
      );
      expect(result.isBudgetUsedUp, isTrue);
      expect(result.weekdayLimitMinor, 0);
      expect(result.weekendLimitMinor, 0);
      expect(result.leftTodayMinor, 0);
      expect(result.overTodayMinor, kes(200));
      expect(result.leftThisMonthMinor, -kes(2200));
    });

    test('gives zero limits with no budget, or exactly none left', () {
      for (final spent in [0, kes(5000)]) {
        final result = SafeToSpend.calculate(
          budgetMinor: spent,
          entries: [if (spent > 0) food(eat(2026, 10, 2), spent)],
          today: monday,
        );
        expect(result.todayLimitMinor, 0);
        expect(result.isBudgetUsedUp, isTrue);
      }
    });

    test('gives the whole remainder on the last day of the month', () {
      final result = SafeToSpend.calculate(
        budgetMinor: kes(30000),
        entries: [food(eat(2026, 10, 10), kes(29000))],
        today: CalendarDate(2026, 10, 31),
        weekendWeightPercent: 250,
      );
      expect(result.weekdaysLeft + result.weekendDaysLeft, 1);
      expect(result.todayLimitMinor, kes(1000));
    });

    test('starts fresh on the first of the month', () {
      final result = SafeToSpend.calculate(
        budgetMinor: kes(30000),
        entries: [food(eat(2026, 10, 31, 23), kes(5000))],
        today: CalendarDate(2026, 11, 1),
      );
      expect(result.spentBeforeTodayMinor, 0);
      expect(result.weekdaysLeft, 21);
      expect(result.weekendDaysLeft, 9);
      expect(result.weekdayLimitMinor, kes(1000));
    });

    test('places spending on Nairobi days', () {
      final result = SafeToSpend.calculate(
        budgetMinor: kes(30000),
        entries: [
          // 00:30 EAT on the 26th: today.
          food(DateTime.utc(2026, 10, 25, 21, 30), kes(100)),
          // 23:30 EAT on the 25th: before today.
          food(DateTime.utc(2026, 10, 25, 20, 30), kes(200)),
          // 00:30 EAT on 1 November: next month.
          food(DateTime.utc(2026, 10, 31, 21, 30), kes(400)),
          // Tomorrow.
          food(eat(2026, 10, 27), kes(800)),
        ],
        today: monday,
      );
      expect(result.spentTodayMinor, kes(100));
      expect(result.spentBeforeTodayMinor, kes(200));
    });

    test('counts only day-to-day spending, net of refunds', () {
      final result = SafeToSpend.calculate(
        budgetMinor: kes(30000),
        entries: [
          food(eat(2026, 10, 5), kes(3000)),
          // Rent is planned, not day-to-day.
          entry(
            at: eat(2026, 10, 5),
            amount: kes(20000),
            categoryType: CategoryType.expense,
          ),
          // A refund from the grocer.
          LedgerEntry(
            id: 900,
            accountId: 1,
            occurredAt: eat(2026, 10, 6),
            amountMinor: kes(500),
            direction: TransactionDirection.inflow,
            kind: TransactionKind.reversal,
            isDailySpending: true,
          ),
          // An own transfer in a day-to-day category is still not spending.
          entry(
            at: eat(2026, 10, 7),
            amount: kes(4000),
            isDailySpending: true,
            transferPairId: 7,
          ),
          food(eat(2026, 10, 8), 5000, currency: 'USD'),
        ],
        today: monday,
      );
      expect(result.spentBeforeTodayMinor, kes(2500));
    });

    test('rejects a weekend weight that is not positive', () {
      expect(
        () => SafeToSpend.calculate(
          budgetMinor: 1,
          entries: const [],
          today: monday,
          weekendWeightPercent: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('weekendWeightFromHistory', () {
    List<LedgerEntry> history({required int weekday, required int weekend}) => [
      for (final day in [for (var i = 1; i <= 28; i++) monday.addDays(-i)])
        food(
          eat(day.year, day.month, day.day),
          day.isWeekend ? weekend : weekday,
        ),
    ];

    test('learns the weekend weight from four weeks of spending', () {
      expect(
        weekendWeightFromHistory(
          history(weekday: kes(1000), weekend: kes(2000)),
          today: monday,
        ),
        200,
      );
      expect(
        weekendWeightFromHistory(
          history(weekday: kes(1000), weekend: kes(1000)),
          today: monday,
        ),
        100,
      );
    });

    test('falls back to even with nothing to compare', () {
      expect(weekendWeightFromHistory(const [], today: monday), 100);
      expect(
        weekendWeightFromHistory(
          history(weekday: kes(1000), weekend: 0),
          today: monday,
        ),
        100,
      );
    });

    test('clamps extreme weights', () {
      expect(
        weekendWeightFromHistory(
          history(weekday: kes(10), weekend: kes(5000)),
          today: monday,
        ),
        maxWeekendWeightPercent,
      );
      expect(
        weekendWeightFromHistory(
          history(weekday: kes(5000), weekend: kes(10)),
          today: monday,
        ),
        minWeekendWeightPercent,
      );
    });

    test('ignores today and anything older than four weeks', () {
      final entries = [
        ...history(weekday: kes(1000), weekend: kes(1000)),
        food(eat(2026, 10, 26), kes(90000)),
        food(eat(2026, 9, 27), kes(90000)),
      ];
      expect(weekendWeightFromHistory(entries, today: monday), 100);
    });
  });
}
