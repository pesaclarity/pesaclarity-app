import '../reminders/reminder_schedule.dart';
import '../time/week_start.dart';
import 'habit_settings.dart';

/// The id of the Sunday check-in notification, apart from the rest: after
/// the tax reminder and below the budget alerts (from collect + 1000).
const checkInReminderId = collectReminderId + 16;

/// The weekly check-in notification: the next last day of the week (Sunday
/// for a week from Monday, see [FirstWeekday]) at the chosen time, today if
/// it is that day and the time is still ahead of [now]. Safe on the
/// lock screen: no amounts and no categories. Null while the check-in or
/// its notification is off.
Reminder? checkInReminder({
  required DateTime now,
  required HabitSettings settings,
  int? weekStartsOn,
}) {
  final minute = settings.notifyMinuteOfDay;
  if (!settings.sundayCheckIn || minute == null) return null;
  final local = now.toLocal();
  final daysToSunday = (lastWeekday(weekStartsOn) - local.weekday) % 7;
  var at = DateTime(
    local.year,
    local.month,
    local.day + daysToSunday,
    minute ~/ 60,
    minute % 60,
  );
  if (!at.isAfter(local)) {
    at = DateTime(at.year, at.month, at.day + 7, at.hour, at.minute);
  }
  return Reminder(
    id: checkInReminderId,
    kind: ReminderKind.weeklyCheckIn,
    at: at.toUtc(),
    title: 'Your week in three lines is ready',
    body: 'Open Pesa Clarity to read it.',
  );
}
