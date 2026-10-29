/// Fixed East Africa Time offset (UTC+3), used as Kenya's standard offset.
const Duration nairobiUtcOffset = Duration(hours: 3);

/// Manages the user's active timezone for the application.
/// Defaults to the device's local timezone (based on user location)
/// and can be synchronized with the local database settings.
class UserTimeZone {
  UserTimeZone._();

  static Duration? _overrideOffset;
  static String? _overrideName;

  /// The active UTC offset for calendar dates and timestamps in the UI.
  static Duration get currentOffset =>
      _overrideOffset ?? DateTime.now().timeZoneOffset;

  /// The active timezone abbreviation or formatted offset.
  static String get currentName {
    if (_overrideName != null && _overrideName!.isNotEmpty) {
      return _overrideName!;
    }
    final name = DateTime.now().timeZoneName;
    return name.isNotEmpty ? name : formatOffset(currentOffset);
  }

  /// Sets an explicit timezone offset and optional display name.
  static void set(Duration offset, {String? name}) {
    _overrideOffset = offset;
    _overrideName = name;
  }

  /// Reverts to the user device's local timezone.
  static void resetToDevice() {
    _overrideOffset = null;
    _overrideName = null;
  }

  /// Formats an offset duration as `UTC+03:00` or `UTC-05:00`.
  static String formatOffset(Duration offset) {
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return 'UTC$sign$hours:$minutes';
  }
}

/// [instant] formatted in user local/timezone wall-clock time, for example `2026-10-03 09:15`.
String formatTimestamp(
  DateTime instant, {
  Duration? offset,
  bool includeTimezone = false,
}) {
  final tzOffset = offset ?? UserTimeZone.currentOffset;
  final local = instant.toUtc().add(tzOffset);
  String two(int n) => n.toString().padLeft(2, '0');
  final base =
      '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
  if (!includeTimezone) return base;
  return '$base (${UserTimeZone.formatOffset(tzOffset)})';
}

/// A day on the calendar, timezone aware, with no time of day.
class CalendarDate implements Comparable<CalendarDate> {
  /// Normalises out-of-range values, so `CalendarDate(2026, 2, 31)` is 3 March.
  factory CalendarDate(int year, int month, int day) {
    final utc = DateTime.utc(year, month, day);
    return CalendarDate._(utc.year, utc.month, utc.day);
  }

  const CalendarDate._(this.year, this.month, this.day);

  /// The local calendar date of [instant] according to the user's active timezone.
  factory CalendarDate.local(DateTime instant) {
    final offset = UserTimeZone.currentOffset;
    final shifted = instant.toUtc().add(offset);
    return CalendarDate._(shifted.year, shifted.month, shifted.day);
  }

  /// Resolves the calendar date of [instant] using [offset] if provided,
  /// otherwise uses [UserTimeZone.currentOffset].
  factory CalendarDate.of(DateTime instant, [Duration? offset]) {
    final tzOffset = offset ?? UserTimeZone.currentOffset;
    final shifted = instant.toUtc().add(tzOffset);
    return CalendarDate._(shifted.year, shifted.month, shifted.day);
  }

  /// The Nairobi date of [instant], whatever zone the [DateTime] is in.
  factory CalendarDate.nairobi(DateTime instant) {
    final local = instant.toUtc().add(nairobiUtcOffset);
    return CalendarDate._(local.year, local.month, local.day);
  }

  /// Today's date in the user's active timezone.
  factory CalendarDate.today([DateTime Function()? now]) {
    final current = now != null ? now() : DateTime.now();
    return CalendarDate.of(current);
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
  DateTime get nairobiStartInstant => _utc.subtract(nairobiUtcOffset);

  /// The UTC instant at which this date starts in the user's active timezone.
  DateTime get startInstant => _utc.subtract(UserTimeZone.currentOffset);

  /// The UTC instant at which this date starts for a given [offset].
  DateTime startInstantAt(Duration offset) => _utc.subtract(offset);

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

  /// The local month of [instant] in the user's active timezone.
  factory YearMonth.local(DateTime instant) =>
      CalendarDate.local(instant).yearMonth;

  /// Timezone-aware month of [instant].
  factory YearMonth.of(DateTime instant, [Duration? offset]) =>
      CalendarDate.of(instant, offset).yearMonth;

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

  /// The UTC instant at which this month starts in the user's active timezone.
  DateTime get startInstant => firstDay.startInstant;

  /// The UTC instant at which this month starts in Nairobi.
  DateTime get nairobiStartInstant => firstDay.nairobiStartInstant;

  /// The UTC instant at which the next month starts in the user's active timezone (exclusive end).
  DateTime get endInstant => next.startInstant;

  /// The UTC instant at which the next month starts in Nairobi (exclusive end).
  DateTime get nairobiEndInstant => next.nairobiStartInstant;

  @override
  int compareTo(YearMonth other) => key.compareTo(other.key);

  @override
  bool operator ==(Object other) => other is YearMonth && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => '$year-${month.toString().padLeft(2, '0')}';
}
