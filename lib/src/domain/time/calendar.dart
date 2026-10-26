/// Kenya keeps East Africa Time, UTC+3, all year with no daylight saving, so a
/// fixed offset is exact and needs no time-zone database.
const Duration nairobiUtcOffset = Duration(hours: 3);

/// A day on the calendar in Nairobi, with no time of day.
class CalendarDate implements Comparable<CalendarDate> {
  /// Normalises out-of-range values, so `CalendarDate(2026, 2, 31)` is 3 March.
  factory CalendarDate(int year, int month, int day) {
    final utc = DateTime.utc(year, month, day);
    return CalendarDate._(utc.year, utc.month, utc.day);
  }

  const CalendarDate._(this.year, this.month, this.day);

  /// The Nairobi date of [instant], whatever zone the [DateTime] is in.
  factory CalendarDate.nairobi(DateTime instant) {
    final local = instant.toUtc().add(nairobiUtcOffset);
    return CalendarDate._(local.year, local.month, local.day);
  }

  final int year;
  final int month;
  final int day;

  /// [DateTime.monday] (1) to [DateTime.sunday] (7).
  int get weekday => _utc.weekday;

  bool get isWeekend =>
      weekday == DateTime.saturday || weekday == DateTime.sunday;

  YearMonth get yearMonth => YearMonth(year, month);

  CalendarDate addDays(int days) => CalendarDate(year, month, day + days);

  /// Whole days from this date to [other]; negative when [other] is earlier.
  int daysUntil(CalendarDate other) =>
      other._utc.difference(_utc).inHours ~/ Duration.hoursPerDay;

  /// The UTC instant at which this date starts in Nairobi (00:00 EAT).
  DateTime get startInstant => _utc.subtract(nairobiUtcOffset);

  bool isBefore(CalendarDate other) => compareTo(other) < 0;

  bool isAfter(CalendarDate other) => compareTo(other) > 0;

  DateTime get _utc => DateTime.utc(year, month, day);

  @override
  int compareTo(CalendarDate other) => _key.compareTo(other._key);

  int get _key => year * 10000 + month * 100 + day;

  @override
  bool operator ==(Object other) => other is CalendarDate && other._key == _key;

  @override
  int get hashCode => _key.hashCode;

  @override
  String toString() =>
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}

/// A calendar month, stored in the database as `yyyymm` (e.g. 202611).
class YearMonth implements Comparable<YearMonth> {
  /// Normalises out-of-range months, so `YearMonth(2026, 13)` is January 2027.
  factory YearMonth(int year, int month) {
    final utc = DateTime.utc(year, month);
    return YearMonth._(utc.year, utc.month);
  }

  const YearMonth._(this.year, this.month);

  /// Parses a `yyyymm` key.
  factory YearMonth.fromKey(int key) {
    final month = key % 100;
    if (month < 1 || month > 12) {
      throw ArgumentError.value(key, 'key', 'not a yyyymm month');
    }
    return YearMonth._(key ~/ 100, month);
  }

  /// The Nairobi month of [instant].
  factory YearMonth.nairobi(DateTime instant) =>
      CalendarDate.nairobi(instant).yearMonth;

  final int year;
  final int month;

  int get key => year * 100 + month;

  int get dayCount => DateTime.utc(year, month + 1, 0).day;

  CalendarDate get firstDay => CalendarDate(year, month, 1);

  CalendarDate get lastDay => CalendarDate(year, month, dayCount);

  YearMonth get next => YearMonth(year, month + 1);

  YearMonth get previous => YearMonth(year, month - 1);

  YearMonth addMonths(int months) => YearMonth(year, month + months);

  /// Whole months from this month to [other]; negative when [other] is earlier.
  int monthsUntil(YearMonth other) =>
      (other.year - year) * 12 + other.month - month;

  bool contains(CalendarDate date) => date.year == year && date.month == month;

  /// The UTC instant at which this month starts in Nairobi.
  DateTime get startInstant => firstDay.startInstant;

  /// The UTC instant at which the next month starts in Nairobi (exclusive end).
  DateTime get endInstant => next.startInstant;

  @override
  int compareTo(YearMonth other) => key.compareTo(other.key);

  @override
  bool operator ==(Object other) => other is YearMonth && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}
