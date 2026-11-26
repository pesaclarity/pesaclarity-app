import '../time/week_start.dart';

/// Profile › Habits: which habit cards Home shows, and when the Sunday
/// check-in notification comes.
class HabitSettings {
  const HabitSettings({
    this.noSpendOnHome = true,
    this.sundayCheckIn = true,
    this.notifyMinuteOfDay = defaultNotifyMinuteOfDay,
  });

  /// Reads what [toJson] wrote; missing or unknown values fall back to the
  /// defaults.
  factory HabitSettings.fromJson(Map<String, Object?>? json) {
    const defaults = HabitSettings();
    if (json == null) return defaults;
    bool flag(String key, bool fallback) =>
        json[key] is bool ? json[key]! as bool : fallback;
    final minute = json['notifyMinuteOfDay'];
    return HabitSettings(
      noSpendOnHome: flag('noSpendOnHome', defaults.noSpendOnHome),
      sundayCheckIn: flag('sundayCheckIn', defaults.sundayCheckIn),
      notifyMinuteOfDay: json.containsKey('notifyMinuteOfDay') && minute == null
          ? null
          : minute is int && notifyChoices.contains(minute)
          ? minute
          : defaults.notifyMinuteOfDay,
    );
  }

  /// Sunday at 18:00.
  static const defaultNotifyMinuteOfDay = 18 * 60;

  /// The times offered for the notification on Sunday, in minutes after
  /// midnight; null is no notification.
  static const notifyChoices = <int?>[9 * 60, 12 * 60, 18 * 60, 20 * 60, null];

  /// The no-spend card on Home.
  final bool noSpendOnHome;

  /// The Sunday check-in card on Home.
  final bool sundayCheckIn;

  /// When on Sunday the check-in notification comes; null for none. Only
  /// while [sundayCheckIn] is on.
  final int? notifyMinuteOfDay;

  HabitSettings copyWith({
    bool? noSpendOnHome,
    bool? sundayCheckIn,
    int? Function()? notifyMinuteOfDay,
  }) => HabitSettings(
    noSpendOnHome: noSpendOnHome ?? this.noSpendOnHome,
    sundayCheckIn: sundayCheckIn ?? this.sundayCheckIn,
    notifyMinuteOfDay: notifyMinuteOfDay == null
        ? this.notifyMinuteOfDay
        : notifyMinuteOfDay(),
  );

  Map<String, Object?> toJson() => {
    'noSpendOnHome': noSpendOnHome,
    'sundayCheckIn': sundayCheckIn,
    'notifyMinuteOfDay': notifyMinuteOfDay,
  };
}

/// `Sunday at 18:00` (the last day of the week, see [lastWeekday]), or
/// `Off`.
String notifyLabel(int? minuteOfDay, {int? weekStartsOn}) {
  if (minuteOfDay == null) return 'Off';
  String two(int n) => n.toString().padLeft(2, '0');
  final day = weekdayFullName(lastWeekday(weekStartsOn));
  return '$day at ${two(minuteOfDay ~/ 60)}:${two(minuteOfDay % 60)}';
}
