import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/habits/habit_settings.dart';
import 'package:pesaclarity/src/domain/habits/week_check_in.dart';
import 'package:pesaclarity/src/domain/insights/spending_charts.dart';
import 'package:pesaclarity/src/domain/ledger/activity_feed.dart';
import 'package:pesaclarity/src/domain/plan/bills_calendar.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/domain/time/week_start.dart';

void main() {
  tearDown(FirstWeekday.reset);

  /// Sunday 22 November 2026.
  final sunday = CalendarDate(2026, 11, 22);

  test('a week from Monday starts on the Monday before', () {
    expect(weekStartOn(sunday), CalendarDate(2026, 11, 16));
    expect(weekStartOn(CalendarDate(2026, 11, 16)), CalendarDate(2026, 11, 16));
    expect(weekEndOn(sunday), sunday);
    expect(lastWeekday(), DateTime.sunday);
  });

  test('any day can start the week', () {
    expect(weekStartOn(sunday, DateTime.sunday), sunday);
    expect(weekStartOn(sunday, DateTime.saturday), CalendarDate(2026, 11, 21));
    expect(
      weekStartOn(CalendarDate(2026, 11, 20), DateTime.saturday),
      CalendarDate(2026, 11, 14),
    );
    expect(lastWeekday(DateTime.sunday), DateTime.saturday);
    expect(lastWeekday(DateTime.saturday), DateTime.friday);
  });

  test('the setting reaches week logic that has no provider', () {
    FirstWeekday.set(DateTime.sunday);
    expect(startOfWeek(sunday), sunday);
    expect(isCheckInDay(CalendarDate(2026, 11, 28)), isTrue);
    expect(isCheckInDay(sunday), isFalse);
    expect(notifyLabel(18 * 60), 'Saturday at 18:00');
    expect(ChartWindow.of(ChartPeriod.week, sunday).start, sunday);
    final grid = calendarGridDays(YearMonth(2026, 11));
    expect(grid.first.weekday, DateTime.sunday);
    expect(grid.last.weekday, DateTime.saturday);
  });

  test('weekly totals follow the first day', () {
    final week = weekInOut(
      const [],
      today: sunday,
      weekStartsOn: DateTime.wednesday,
    );
    expect(week.start, CalendarDate(2026, 11, 18));
  });
}
