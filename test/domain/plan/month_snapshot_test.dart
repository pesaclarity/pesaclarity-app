import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/plan/month_plan.dart';
import 'package:pesaclarity/src/domain/plan/month_snapshot.dart';
import 'package:pesaclarity/src/domain/plan/plan_inputs.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  final october = YearMonth(2026, 10);
  final review = MonthReview.of(
    MonthPlan.build(
      month: october,
      recurring: [
        RecurringBill(
          id: 1,
          name: 'Rent',
          categoryId: 2,
          amountMinor: kes(25000),
          frequency: RecurrenceFrequency.monthly,
          startDate: CalendarDate(2026, 1, 5),
        ),
      ],
      items: const [],
      categories: const [PlanCategory(id: 2, type: CategoryType.expense)],
    ),
    [
      entry(
        at: eat(2026, 10, 5),
        amount: kes(20000),
        categoryId: 2,
        categoryType: CategoryType.expense,
      ),
      entry(at: eat(2026, 10, 6), amount: kes(300)),
    ],
  );

  group('MonthSnapshot.freeze', () {
    test('refuses until the month has ended in Nairobi', () {
      expect(
        () => MonthSnapshot.freeze(review, now: eat(2026, 10, 31, 23, 59)),
        throwsStateError,
      );
    });

    test('freezes plan, actuals and arrears at 00:00 EAT on the 1st', () {
      final now = eat(2026, 11, 1, 0);
      final snapshot = MonthSnapshot.freeze(review, now: now);
      expect(snapshot.month, october);
      expect(snapshot.frozenAt, now);
      expect(snapshot.frozenAt.isUtc, isTrue);
      expect(
        snapshot.categories.map(
          (c) => (c.categoryId, c.plannedMinor, c.actualMinor),
        ),
        [(2, kes(25000), kes(20000)), (null, 0, kes(300))],
      );
      expect(snapshot.carriedArrears.single.amountMinor, kes(5000));
      expect(snapshot.carriedArrears.single.month, YearMonth(2026, 11));
    });
  });

  group('monthsToFreeze', () {
    final now = eat(2027, 1, 3);

    test('lists ended months after the last frozen one, oldest first', () {
      expect(
        monthsToFreeze(
          firstMonth: YearMonth(2026, 8),
          lastFrozen: YearMonth(2026, 10),
          now: now,
        ),
        [YearMonth(2026, 11), YearMonth(2026, 12)],
      );
    });

    test('starts at the first month when nothing is frozen', () {
      expect(monthsToFreeze(firstMonth: YearMonth(2026, 11), now: now), [
        YearMonth(2026, 11),
        YearMonth(2026, 12),
      ]);
    });

    test('is empty when everything is frozen or the month is running', () {
      expect(
        monthsToFreeze(
          firstMonth: YearMonth(2026, 1),
          lastFrozen: YearMonth(2026, 12),
          now: now,
        ),
        isEmpty,
      );
      expect(
        monthsToFreeze(
          firstMonth: YearMonth(2027, 1),
          now: DateTime.utc(2027, 1, 31, 20, 59),
        ),
        isEmpty,
      );
      expect(
        monthsToFreeze(
          firstMonth: YearMonth(2027, 1),
          now: DateTime.utc(2027, 1, 31, 21),
        ),
        [YearMonth(2027, 1)],
      );
    });
  });
}
