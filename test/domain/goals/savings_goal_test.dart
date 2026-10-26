import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/goals/savings_goal.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  final today = CalendarDate(2026, 10, 26);

  SavingsGoal goal({int saved = 0, CalendarDate? date}) => SavingsGoal(
    id: 1,
    name: 'Emergency fund',
    targetMinor: 15000000,
    savedMinor: saved,
    targetDate: date,
  );

  test('progress is saved over target, capped at 1', () {
    expect(goal(saved: 6000000).progress, closeTo(0.4, 1e-9));
    expect(goal(saved: 6000000).remainingMinor, 9000000);
    expect(goal(saved: 20000000).progress, 1);
    expect(goal(saved: 20000000).isReached, isTrue);
  });

  test('the monthly amount counts this month and rounds up', () {
    // October, November and December.
    final g = goal(saved: 6000000, date: CalendarDate(2026, 12, 31));
    expect(g.monthsLeft(today), 3);
    expect(g.monthlyNeededMinor(today), 3000000);

    final odd = goal(saved: 1, date: CalendarDate(2026, 12, 1));
    expect(odd.monthlyNeededMinor(today), 5000000);
  });

  test('a date this month needs the rest now', () {
    final g = goal(saved: 6000000, date: CalendarDate(2026, 10, 31));
    expect(g.monthsLeft(today), 1);
    expect(g.monthlyNeededMinor(today), 9000000);
  });

  test('a passed date needs the whole remainder', () {
    final g = goal(saved: 6000000, date: CalendarDate(2026, 9, 30));
    expect(g.monthsLeft(today), 0);
    expect(g.monthlyNeededMinor(today), 9000000);
  });

  test('a goal with no date has no monthly amount', () {
    expect(goal().monthsLeft(today), isNull);
    expect(goal().monthlyNeededMinor(today), isNull);
  });

  test('a reached goal needs nothing more', () {
    final g = goal(saved: 15000000, date: CalendarDate(2027, 6, 30));
    expect(g.monthlyNeededMinor(today), 0);
  });
}
