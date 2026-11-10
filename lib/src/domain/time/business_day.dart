import 'calendar.dart';

/// When a business's day ends: at midnight, or some hours after it for a
/// place open late. A sale at 1 am before a 6 am end counts on the day
/// before.
class BusinessDay {
  const BusinessDay({this.endsAtHour = 0})
    : assert(endsAtHour >= 0 && endsAtHour < Duration.hoursPerDay);

  /// The day ends at midnight.
  static const midnight = BusinessDay();

  /// The hours after midnight a day can end at, in menu order.
  static const choices = [0, 2, 4, 6];

  /// Hours after midnight the day ends; 0 is midnight.
  final int endsAtHour;

  Duration get _shift => Duration(hours: endsAtHour);

  /// The business day [instant] falls in.
  CalendarDate dayOf(DateTime instant) =>
      CalendarDate.local(instant.subtract(_shift));

  /// When [day] starts.
  DateTime startOf(CalendarDate day) => day.startInstant.add(_shift);

  /// When [day] ends, which is when the next one starts.
  DateTime endOf(CalendarDate day) => startOf(day.addDays(1));

  /// Whether [instant] falls in [day].
  bool contains(CalendarDate day, DateTime instant) =>
      !instant.isBefore(startOf(day)) && instant.isBefore(endOf(day));

  /// `midnight` or `6 am`.
  String get endLabel => labelFor(endsAtHour);

  static String labelFor(int hour) => switch (hour) {
    0 => 'Midnight',
    < 12 => '$hour am',
    12 => 'Noon',
    _ => '${hour - 12} pm',
  };

  static BusinessDay fromJson(Map<String, Object?>? json) {
    final hour = json?['endsAtHour'];
    return hour is int && choices.contains(hour)
        ? BusinessDay(endsAtHour: hour)
        : midnight;
  }

  Map<String, Object?> toJson() => {'endsAtHour': endsAtHour};

  @override
  bool operator ==(Object other) =>
      other is BusinessDay && other.endsAtHour == endsAtHour;

  @override
  int get hashCode => endsAtHour.hashCode;
}
