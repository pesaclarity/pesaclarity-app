import '../time/calendar.dart';

/// Within this many days the next instalment reads as close.
const dueSoonDays = 3;

/// When a loan's next instalment is due: the date the lender's last
/// repayment message gave, or one the person typed.
class NextDue {
  const NextDue({required this.date, this.paidSince = false, this.source});

  final CalendarDate date;

  /// A repayment was recorded on or after [date], by message or by hand.
  final bool paidSince;

  /// The message the date came from; null when the person typed it.
  final DueSource? source;

  /// Where the instalment stands on [today].
  DueStatus statusOn(CalendarDate today) {
    final days = today.daysUntil(date);
    final state = switch (days) {
      0 => DueState.today,
      > dueSoonDays => DueState.later,
      > 0 => DueState.soon,
      _ => paidSince ? DueState.paid : DueState.late,
    };
    return DueStatus(state, days);
  }

  @override
  bool operator ==(Object other) =>
      other is NextDue &&
      other.date == date &&
      other.paidSince == paidSince &&
      other.source == source;

  @override
  int get hashCode => Object.hash(date, paidSince, source);

  @override
  String toString() => 'NextDue($date, paidSince: $paidSince)';
}

/// The repayment message a due date was read from.
class DueSource {
  const DueSource({required this.readAt, this.institutionId, this.account});

  /// When the message came in.
  final DateTime readAt;

  /// The institution whose message it was, such as `kcb`.
  final String? institutionId;

  /// The name of the account the repayment left, for when the institution
  /// is not known.
  final String? account;

  @override
  bool operator ==(Object other) =>
      other is DueSource &&
      other.readAt == readAt &&
      other.institutionId == institutionId &&
      other.account == account;

  @override
  int get hashCode => Object.hash(readAt, institutionId, account);
}

/// How close the next instalment is.
enum DueState {
  /// More than [dueSoonDays] days away.
  later,

  /// Tomorrow, or up to [dueSoonDays] days away.
  soon,

  /// Due today.
  today,

  /// The date passed with no repayment since.
  late,

  /// The date passed and a repayment came in on or after it.
  paid,
}

/// Where an instalment stands on a day.
class DueStatus {
  const DueStatus(this.state, this.days);

  final DueState state;

  /// Days from today to the due date; negative once it has passed.
  final int days;

  /// Days past the due date; 0 until it passes.
  int get daysLate => days < 0 ? -days : 0;

  @override
  bool operator ==(Object other) =>
      other is DueStatus && other.state == state && other.days == days;

  @override
  int get hashCode => Object.hash(state, days);

  @override
  String toString() => 'DueStatus(${state.name}, $days)';
}

/// One payment on a debt: when and how much.
typedef DebtPayment = ({CalendarDate date, int amountMinor});

/// [date] as stored: `yyyymmdd`, the same whatever the phone's time zone.
int dayKey(CalendarDate date) =>
    date.year * 10000 + date.month * 100 + date.day;

/// The date stored as [key] (`yyyymmdd`).
CalendarDate fromDayKey(int key) =>
    CalendarDate(key ~/ 10000, key ~/ 100 % 100, key % 100);
