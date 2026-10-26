import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/plan/plan_inputs.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

RecurringBill bill(
  RecurrenceFrequency frequency,
  CalendarDate start, {
  CalendarDate? end,
}) => RecurringBill(
  id: 1,
  name: 'Test bill',
  amountMinor: 100,
  frequency: frequency,
  startDate: start,
  endDate: end,
);

void main() {
  test('monthly bills keep their day, or the last day of short months', () {
    final rent = bill(RecurrenceFrequency.monthly, CalendarDate(2026, 1, 31));
    expect(rent.dueDatesIn(YearMonth(2026, 1)), [CalendarDate(2026, 1, 31)]);
    expect(rent.dueDatesIn(YearMonth(2026, 2)), [CalendarDate(2026, 2, 28)]);
    expect(rent.dueDatesIn(YearMonth(2028, 2)), [CalendarDate(2028, 2, 29)]);
    expect(rent.dueDatesIn(YearMonth(2026, 4)), [CalendarDate(2026, 4, 30)]);
    expect(rent.dueDatesIn(YearMonth(2027, 1)), [CalendarDate(2027, 1, 31)]);
  });

  test('nothing is due before the start or after the end', () {
    final b = bill(
      RecurrenceFrequency.monthly,
      CalendarDate(2026, 10, 15),
      end: CalendarDate(2026, 12, 10),
    );
    expect(b.dueDatesIn(YearMonth(2026, 9)), isEmpty);
    expect(b.dueDatesIn(YearMonth(2026, 11)), hasLength(1));
    expect(b.dueDatesIn(YearMonth(2026, 12)), isEmpty);
  });

  test('quarterly and yearly bills skip the months between', () {
    final school = bill(
      RecurrenceFrequency.quarterly,
      CalendarDate(2026, 1, 5),
    );
    final due = [
      for (var m = 1; m <= 12; m++)
        if (school.dueDatesIn(YearMonth(2026, m)).isNotEmpty) m,
    ];
    expect(due, [1, 4, 7, 10]);

    final insurance = bill(
      RecurrenceFrequency.yearly,
      CalendarDate(2026, 3, 1),
    );
    expect(insurance.dueDatesIn(YearMonth(2026, 3)), hasLength(1));
    expect(insurance.dueDatesIn(YearMonth(2026, 9)), isEmpty);
    expect(insurance.dueDatesIn(YearMonth(2027, 3)), hasLength(1));
  });

  test('weekly bills fall four or five times a month', () {
    final chama = bill(RecurrenceFrequency.weekly, CalendarDate(2026, 10, 1));
    expect(chama.dueDatesIn(YearMonth(2026, 10)), [
      CalendarDate(2026, 10, 1),
      CalendarDate(2026, 10, 8),
      CalendarDate(2026, 10, 15),
      CalendarDate(2026, 10, 22),
      CalendarDate(2026, 10, 29),
    ]);
    expect(chama.dueDatesIn(YearMonth(2026, 11)), [
      CalendarDate(2026, 11, 5),
      CalendarDate(2026, 11, 12),
      CalendarDate(2026, 11, 19),
      CalendarDate(2026, 11, 26),
    ]);
    expect(
      chama.dueDatesIn(YearMonth(2027, 1)).first,
      CalendarDate(2027, 1, 7),
    );
  });

  test('weekly bills respect start and end inside the month', () {
    final b = bill(
      RecurrenceFrequency.weekly,
      CalendarDate(2026, 10, 20),
      end: CalendarDate(2026, 11, 3),
    );
    expect(b.dueDatesIn(YearMonth(2026, 9)), isEmpty);
    expect(b.dueDatesIn(YearMonth(2026, 10)), [
      CalendarDate(2026, 10, 20),
      CalendarDate(2026, 10, 27),
    ]);
    expect(b.dueDatesIn(YearMonth(2026, 11)), [CalendarDate(2026, 11, 3)]);
    expect(b.dueDatesIn(YearMonth(2026, 12)), isEmpty);
  });
}
