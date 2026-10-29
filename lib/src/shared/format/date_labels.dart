import '../../domain/time/calendar.dart';

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// `Monday`.
String weekdayName(CalendarDate date) => _weekdays[date.weekday - 1];

/// `26 Oct`.
String shortDate(CalendarDate date) => '${date.day} ${_months[date.month - 1]}';

/// `Monday, 26 Oct`.
String longDate(CalendarDate date) =>
    '${weekdayName(date)}, ${shortDate(date)}';

/// `October`.
String monthName(YearMonth month) => _monthNames[month.month - 1];

/// `Today`, `Yesterday`, or `Fri 23 Oct`.
String dayHeading(CalendarDate date, {required CalendarDate today}) {
  if (date == today) return 'Today';
  if (date == today.addDays(-1)) return 'Yesterday';
  return '${weekdayName(date).substring(0, 3)} ${shortDate(date)}';
}

/// `in 10 days`, `tomorrow`, `today`, or `3 days late`.
String relativeDays(CalendarDate date, {required CalendarDate today}) {
  final days = today.daysUntil(date);
  if (days == 0) return 'today';
  if (days == 1) return 'tomorrow';
  if (days > 1) return 'in $days days';
  return days == -1 ? '1 day late' : '${-days} days late';
}

/// Formats an instant in the user's active timezone: `2026-10-29 16:45`.
String formatDateTime(
  DateTime instant, {
  Duration? offset,
  bool includeTimezone = false,
}) =>
    formatTimestamp(instant, offset: offset, includeTimezone: includeTimezone);

/// Formats time in the user's active timezone: `16:45`.
String formatTime(DateTime instant, {Duration? offset}) {
  final tzOffset = offset ?? UserTimeZone.currentOffset;
  final local = instant.toUtc().add(tzOffset);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}';
}
