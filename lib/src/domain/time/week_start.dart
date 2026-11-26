import 'calendar.dart';

/// The day the person's week starts on (Profile › Week starts on), as a
/// [DateTime] weekday: Monday unless they chose another day.
///
/// Home's tabs, weekly totals, the weekly check-in, no-spend days, week
/// by week, charts and Ask's "this week" all follow it. Providers pass the
/// setting explicitly; [current] is what the app last loaded, for code that
/// has no provider to read it from (Ask's period words).
class FirstWeekday {
  FirstWeekday._();

  static int _current = DateTime.monday;

  /// The weekday the week starts on, as last loaded.
  static int get current => _current;

  static void set(int weekday) {
    assert(
      weekday >= DateTime.monday && weekday <= DateTime.sunday,
      'a weekday',
    );
    _current = weekday;
  }

  /// Back to Monday, for tests.
  static void reset() => _current = DateTime.monday;
}

/// The first day of the week holding [date], for a week that starts on
/// [firstDay] ([FirstWeekday.current] when not given).
CalendarDate weekStartOn(CalendarDate date, [int? firstDay]) {
  final first = firstDay ?? FirstWeekday.current;
  return date.addDays(-((date.weekday - first) % 7));
}

/// The last day of the week holding [date].
CalendarDate weekEndOn(CalendarDate date, [int? firstDay]) =>
    weekStartOn(date, firstDay).addDays(6);

/// The weekday the week ends on: Sunday for a week from Monday.
int lastWeekday([int? firstDay]) =>
    ((firstDay ?? FirstWeekday.current) + 5) % 7 + 1;

/// Weekday names, Monday first, as Profile lists them.
const weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// `Monday` for [DateTime.monday].
String weekdayFullName(int weekday) => weekdayNames[weekday - 1];
