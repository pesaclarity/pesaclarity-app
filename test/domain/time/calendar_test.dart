import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  group('CalendarDate.nairobi', () {
    test('rolls over at 21:00 UTC, which is midnight EAT', () {
      expect(
        CalendarDate.nairobi(DateTime.utc(2026, 10, 25, 20, 59)),
        CalendarDate(2026, 10, 25),
      );
      expect(
        CalendarDate.nairobi(DateTime.utc(2026, 10, 25, 21)),
        CalendarDate(2026, 10, 26),
      );
    });

    test('crosses month and year boundaries', () {
      expect(
        CalendarDate.nairobi(DateTime.utc(2026, 10, 31, 22)),
        CalendarDate(2026, 11, 1),
      );
      expect(
        CalendarDate.nairobi(DateTime.utc(2026, 12, 31, 21, 30)),
        CalendarDate(2027, 1, 1),
      );
    });

    test('ignores the zone the DateTime was created in', () {
      final utc = DateTime.utc(2026, 3, 1, 22);
      expect(CalendarDate.nairobi(utc.toLocal()), CalendarDate(2026, 3, 2));
    });
  });

  group('CalendarDate', () {
    test('normalises and adds days across months and leap years', () {
      expect(CalendarDate(2026, 2, 31), CalendarDate(2026, 3, 3));
      expect(CalendarDate(2028, 2, 28).addDays(1), CalendarDate(2028, 2, 29));
      expect(CalendarDate(2026, 12, 31).addDays(1), CalendarDate(2027, 1, 1));
    });

    test('counts days and weekends', () {
      expect(
        CalendarDate(2026, 10, 1).daysUntil(CalendarDate(2026, 11, 1)),
        31,
      );
      expect(
        CalendarDate(2026, 11, 1).daysUntil(CalendarDate(2026, 10, 1)),
        -31,
      );
      expect(CalendarDate(2026, 10, 24).isWeekend, isTrue); // Saturday
      expect(CalendarDate(2026, 10, 26).isWeekend, isFalse); // Monday
    });

    test('starts at 00:00 EAT', () {
      expect(
        CalendarDate(2026, 11, 1).startInstant,
        DateTime.utc(2026, 10, 31, 21),
      );
    });

    test('compares and prints', () {
      expect(
        CalendarDate(2026, 1, 9).isBefore(CalendarDate(2026, 1, 10)),
        isTrue,
      );
      expect(CalendarDate(2026, 1, 9).toString(), '2026-01-09');
    });
  });

  group('YearMonth', () {
    test('round-trips the yyyymm key', () {
      expect(YearMonth.fromKey(202611), YearMonth(2026, 11));
      expect(YearMonth(2026, 11).key, 202611);
      expect(() => YearMonth.fromKey(202613), throwsArgumentError);
    });

    test('knows its days and neighbours', () {
      expect(YearMonth(2026, 2).dayCount, 28);
      expect(YearMonth(2028, 2).dayCount, 29);
      expect(YearMonth(2026, 12).next, YearMonth(2027, 1));
      expect(YearMonth(2027, 1).previous, YearMonth(2026, 12));
      expect(YearMonth(2026, 11).monthsUntil(YearMonth(2027, 2)), 3);
      expect(YearMonth(2026, 11).lastDay, CalendarDate(2026, 11, 30));
    });

    test('spans Nairobi instants', () {
      final month = YearMonth(2026, 11);
      expect(month.startInstant, DateTime.utc(2026, 10, 31, 21));
      expect(month.endInstant, DateTime.utc(2026, 11, 30, 21));
      expect(YearMonth.nairobi(DateTime.utc(2026, 10, 31, 21)), month);
    });
  });
}
