import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/debts/next_due.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  final due = CalendarDate(2026, 12, 5);
  final unpaid = NextDue(date: due);
  final paid = NextDue(date: due, paidSince: true);

  DueStatus on(NextDue next, int month, int day) =>
      next.statusOn(CalendarDate(2026, month, day));

  group('statusOn', () {
    test('is later more than three days ahead', () {
      expect(on(unpaid, 11, 21), const DueStatus(DueState.later, 14));
      // The last day before it turns close.
      expect(on(unpaid, 12, 1), const DueStatus(DueState.later, 4));
    });

    test('is soon from three days to one day ahead', () {
      expect(on(unpaid, 12, 2), const DueStatus(DueState.soon, 3));
      expect(on(unpaid, 12, 3), const DueStatus(DueState.soon, 2));
      expect(on(unpaid, 12, 4), const DueStatus(DueState.soon, 1));
    });

    test('is today on the day, paid or not', () {
      expect(on(unpaid, 12, 5), const DueStatus(DueState.today, 0));
      expect(on(paid, 12, 5), const DueStatus(DueState.today, 0));
    });

    test('is late from the next day with no repayment since', () {
      final late = on(unpaid, 12, 6);
      expect(late, const DueStatus(DueState.late, -1));
      expect(late.daysLate, 1);
      expect(on(unpaid, 12, 8).daysLate, 3);
    });

    test('is paid once the day passed with a repayment since', () {
      expect(on(paid, 12, 6).state, DueState.paid);
    });

    test('counts days across a month and a year end', () {
      final newYear = NextDue(date: CalendarDate(2027, 1, 2));
      expect(on(newYear, 12, 30), const DueStatus(DueState.soon, 3));
    });
  });

  test('stores a date as yyyymmdd and reads it back', () {
    expect(dayKey(CalendarDate(2026, 12, 5)), 20261205);
    expect(fromDayKey(20270115), CalendarDate(2027, 1, 15));
  });
}
