import '../../../domain/time/calendar.dart';

const _months = [
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

/// The month's full name, such as "October".
String monthName(YearMonth month) => _months[month.month - 1];

/// The month's three-letter name, such as "Oct".
String shortMonthName(YearMonth month) => monthName(month).substring(0, 3);

/// A Nairobi date such as "26 October 2026".
String longDate(CalendarDate date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';
