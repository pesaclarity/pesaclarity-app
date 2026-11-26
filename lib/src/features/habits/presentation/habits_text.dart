import '../../../domain/habits/no_spend_days.dart';
import '../../../domain/habits/week_check_in.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';

/// The words of no-spend days and the weekly check-in.
abstract final class HabitsText {
  static const checkInTitle = 'Your week in three lines';
  static const checkInReady = 'Weekly check-in · ready';
  static const weekTitle = 'Your week';
  static const whatChanged = 'What changed';
  static const wentWell = 'One thing that went well';
  static const nextWeek = 'For next week';
  static const workedOut =
      'Worked out on this phone from your Insights. Nothing is sent anywhere.';
  static const seeInsights = 'See Insights';

  static const noSpendExplained =
      'A day with no spending. Bills, moves between your own accounts and '
      'savings do not count as spending.';
  static const leftOutShort = 'bills, moves and savings do not count';
  static const streakNow = 'Streak now';
  static const longestThisMonth = 'Longest this month';
  static const none = 'None';
  static const today = 'Today';

  static const habits = 'Habits';
  static const noSpendSetting = 'No-spend days on Home';
  static const noSpendSettingDetail = 'A count for the week and a plain streak';
  static const checkInSetting = 'Weekly check-in';
  static const checkInSettingDetail = 'Three lines on your week, on Home';
  static const notifyMe = 'Notify me';
  static const notifyNeedsReminders = 'Shows while Reminders is on';
  static const settingsFooter =
      'Turning one off hides it from Home. Nothing else changes.';

  /// `3 no-spend days this week`.
  static String weekCount(int count) =>
      '$count no-spend ${count == 1 ? 'day' : 'days'} this week';

  /// `2 days`.
  static String days(int count) => '$count ${count == 1 ? 'day' : 'days'}';

  /// `Streak: 2 days · bills, moves and savings do not count`.
  static String streakLine(int streak) =>
      'Streak: ${days(streak)} · $leftOutShort';

  /// `No-spend days in Nov`.
  static String monthCount(YearMonth month) =>
      'No-spend days in ${monthName(month).substring(0, 3)}';

  /// `Mon 16 to Sun 22 Nov`.
  static String weekRange(CalendarDate start, CalendarDate end) {
    final from = start.month == end.month
        ? '${_day3(start)} ${start.day}'
        : '${_day3(start)} ${shortDate(start)}';
    return '$from to ${_day3(end)} ${shortDate(end)}';
  }

  static String _day3(CalendarDate date) => weekdayName(date).substring(0, 3);

  /// Why a no-spend day with money out still counts, such as `Friday had a
  /// KPLC bill and a move to Chumz. Neither breaks a no-spend day.`
  static String leftOutNote(DaySpend day) {
    final parts = <String>{
      for (final item in day.leftOut)
        switch (item.kind) {
          LeftOutKind.bill =>
            item.name == null ? 'a bill' : 'a ${item.name} bill',
          LeftOutKind.move =>
            item.name == null
                ? 'a move between your accounts'
                : 'a move to ${item.name}',
          LeftOutKind.saving =>
            item.name == null
                ? 'money put into savings'
                : 'money put into ${item.name}',
          LeftOutKind.smallCash => 'a little cash',
        },
    }.toList();
    final listed = parts.length == 1
        ? parts.single
        : '${parts.take(parts.length - 1).join(', ')} and ${parts.last}';
    final ending = switch (parts.length) {
      1 => 'It does not break a no-spend day.',
      2 => 'Neither breaks a no-spend day.',
      _ => 'None of them breaks a no-spend day.',
    };
    return '${weekdayName(day.date)} had $listed. $ending';
  }

  /// What changed on last week, such as `You spent 4,100 less than last
  /// week, most of it on eating out.`
  static String changed(
    WeekCheckIn week,
    String Function(int minor) money,
    Map<int, String> categories,
  ) {
    if (week.spentMinor == 0 && week.lastWeekMinor == 0) {
      return 'No spending this week or the same days of last week.';
    }
    if (week.aboutTheSame) return 'You spent about the same as last week.';
    final change = week.changeMinor;
    final where = _category(week.mostChanged?.categoryId, categories);
    return 'You spent ${money(change.abs())} '
        '${change < 0 ? 'less' : 'more'} than last week'
        '${where == null ? '.' : ', most of it on $where.'}';
  }

  /// One thing that went well, such as `Three no-spend days, the most this
  /// month.`
  static String wentWellLine(
    WeekCheckIn week,
    String Function(int minor) money,
    Map<int, String> categories,
  ) {
    final count = week.noSpendDays;
    if (count > 0) {
      final days = '${_number(count)} no-spend ${count == 1 ? 'day' : 'days'}';
      return week.noSpendBestThisMonth && count > 1
          ? '$days, the most this month.'
          : '$days.';
    }
    if (week.mostDown case final down?) {
      if (_category(down.categoryId, categories) case final name?) {
        return '${_capital(name)} came down by '
            '${money(-down.changeMinor)} on last week.';
      }
    }
    if (!week.aboutTheSame && week.changeMinor < 0) {
      return 'You spent less than last week.';
    }
    return 'Your records are up to date for the week.';
  }

  /// One suggestion for next week, such as `Transport is 1,900 above its
  /// usual week. Try keeping it to 1,500.`
  static String nextWeekLine(
    WeekCheckIn week,
    String Function(int minor) money,
    Map<int, String> categories,
  ) {
    final above = week.aboveUsual;
    final name = _category(above?.categoryId, categories);
    if (above == null || name == null) {
      return 'Nothing is far above its usual week. Keep the same pace.';
    }
    // The usual week, to the nearest hundred.
    final usual = (week.usualMinor + 5000) ~/ 10000 * 10000;
    return '${_capital(name)} is ${money(above.changeMinor)} above its usual '
        'week. Try keeping it to ${money(usual)}.';
  }

  /// A category's name as it reads mid-sentence: `eating out`, but `KPLC`.
  static String? _category(int? id, Map<int, String> names) {
    final name = id == null ? null : names[id];
    if (name == null || name.isEmpty) return null;
    final rest = name.substring(1);
    return rest == rest.toLowerCase() ? name[0].toLowerCase() + rest : name;
  }

  static String _capital(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  static String _number(int n) => switch (n) {
    1 => 'One',
    2 => 'Two',
    3 => 'Three',
    4 => 'Four',
    5 => 'Five',
    6 => 'Six',
    7 => 'Seven',
    _ => '$n',
  };
}
