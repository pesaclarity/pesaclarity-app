import '../../core/money/money.dart';
import '../enums.dart';
import '../time/calendar.dart';

/// Where a goal's money is kept: one pocket of a savings account the app
/// keeps, such as a goal in a savings app.
class GoalBacking {
  const GoalBacking({
    required this.accountId,
    required this.accountName,
    required this.pocketId,
    required this.pocketName,
    this.lockedUntil,
  });

  /// The savings account and its name, such as Chumz.
  final int accountId;
  final String accountName;
  final int pocketId;
  final String pocketName;

  /// The day the savings app unlocks the pocket; null when it is open.
  final CalendarDate? lockedUntil;

  /// Whether the money is still locked on [day]. It opens on the day it is
  /// locked until.
  bool isLockedOn(CalendarDate day) =>
      lockedUntil != null && day.isBefore(lockedUntil!);
}

/// Something the user is saving for, with what is put aside so far.
class SavingsGoal {
  SavingsGoal({
    required this.id,
    required this.name,
    required this.targetMinor,
    this.savedMinor = 0,
    this.targetDate,
    String? currency,
    this.status = GoalStatus.active,
    this.backing,
  }) : currency = currency ?? BaseCurrency.code,
       assert(targetMinor > 0, 'targets are positive'),
       assert(savedMinor >= 0, 'savings are never negative');

  final int id;
  final String name;
  final int targetMinor;

  /// What is put aside: what the person typed, or with a [backing], what
  /// its pocket holds.
  final int savedMinor;
  final CalendarDate? targetDate;
  final String currency;
  final GoalStatus status;

  /// The savings pocket the money is kept in; null for a goal whose saved
  /// amount the person types.
  final GoalBacking? backing;

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
