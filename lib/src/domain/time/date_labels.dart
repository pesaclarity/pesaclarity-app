import 'calendar.dart';

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

/// A month as the app shows it, for example `Mar 2028`.
String monthLabel(YearMonth month) =>
    '${_months[month.month - 1]} ${month.year}';

/// A month's short name, for example `Mar`.
String monthName(YearMonth month) => _months[month.month - 1];

/// A day as the app shows it, for example `31 Jan`, with the year added
/// when it is not [thisYear].
String dayLabel(CalendarDate date, {int? thisYear}) {
  final label = '${date.day} ${_months[date.month - 1]}';
  return thisYear == null || date.year == thisYear
      ? label
      : '$label ${date.year}';
}

/// A day with its year, for example `31 Jan 2027`.
String dateLabel(CalendarDate date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';
