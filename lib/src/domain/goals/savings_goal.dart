import '../enums.dart';
import '../time/calendar.dart';

/// Something the user is saving for, with what is put aside so far.
class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetMinor,
    this.savedMinor = 0,
    this.targetDate,
    this.currency = 'KES',
    this.status = GoalStatus.active,
  }) : assert(targetMinor > 0, 'targets are positive'),
       assert(savedMinor >= 0, 'savings are never negative');

  final int id;
  final String name;
  final int targetMinor;
  final int savedMinor;
  final CalendarDate? targetDate;
  final String currency;
  final GoalStatus status;

  int get remainingMinor =>
      savedMinor >= targetMinor ? 0 : targetMinor - savedMinor;

  bool get isReached => remainingMinor == 0;

  /// Saved over target, from 0 to 1.
  double get progress => isReached ? 1 : savedMinor / targetMinor;

  /// Months left to save in, counting this month, so a goal due at the end
  /// of next month has two. Zero once the date has passed; null with no date.
  int? monthsLeft(CalendarDate today) {
    final date = targetDate;
    if (date == null) return null;
    if (date.isBefore(today)) return 0;
    return today.yearMonth.monthsUntil(date.yearMonth) + 1;
  }

  /// What to put aside each month to reach the target on its date, rounded
  /// up to the minor unit. The whole remainder once the date has passed;
  /// null with no date.
  int? monthlyNeededMinor(CalendarDate today) {
    final months = monthsLeft(today);
    if (months == null) return null;
    if (months == 0) return remainingMinor;
    return (remainingMinor + months - 1) ~/ months;
  }
}
