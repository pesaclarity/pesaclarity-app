import '../time/calendar.dart';

/// Days a rolling plan covers when money has no fixed day: business, gigs.
const rollingPlanDays = 7;

/// The share of money on hand kept back as a buffer, in percent.
const nextMoneyBufferPercent = 10;

/// What tells the plan when money comes next.
enum NextMoneyBasis {
  /// A steady rhythm learnt from messages, such as support every 14 days.
  rhythm,

  /// No fixed day: plan a week at a time.
  rolling,

  /// Nothing expected soon: show how long it lasts.
  noDate,
}

/// Safe to spend for people without a payday: what is on hand now, less
/// bills due before the next money and a small buffer, spread over the days
/// until the next money.
class UntilNextMoney {
  const UntilNextMoney({
    required this.today,
    required this.basis,
    required this.onHandMinor,
    required this.billsMinor,
    required this.bufferMinor,
    required this.days,
    required this.dailyMinor,
    required this.spentTodayMinor,
    this.nextMoney,
    this.lastsUntil,
  });

  /// Works out today's amount.
  ///
  /// [onHandAtStartMinor] is the day-to-day balance at the start of today,
  /// so spending during the day lowers [leftTodayMinor] but not the daily
  /// amount. [billsMinor] are bills due before the next money (or within
  /// the plan's days). [paceMinor] is the usual daily spending, used to say
  /// how long the money lasts.
  factory UntilNextMoney.calculate({
    required CalendarDate today,
    required NextMoneyBasis basis,
    required int onHandAtStartMinor,
    required int billsMinor,
    required int spentTodayMinor,
    required int paceMinor,
    CalendarDate? nextMoney,
  }) {
    final onHand = onHandAtStartMinor < 0 ? 0 : onHandAtStartMinor;
    final buffer = onHand * nextMoneyBufferPercent ~/ 100;
    final usable = onHand - buffer - billsMinor;
    final days = switch (basis) {
      NextMoneyBasis.rhythm when nextMoney != null =>
        today.daysUntil(nextMoney) < 1 ? 1 : today.daysUntil(nextMoney),
      NextMoneyBasis.noDate when paceMinor > 0 => _atLeastOne(
        (onHand - billsMinor) ~/ paceMinor,
      ),
      _ => rollingPlanDays,
    };
    final daily = usable <= 0 ? 0 : usable ~/ days;
    final lastsDays = paceMinor <= 0
        ? null
        : (onHand - billsMinor) ~/ paceMinor;
    return UntilNextMoney(
      today: today,
      basis: basis,
      onHandMinor: onHand,
      billsMinor: billsMinor,
      bufferMinor: buffer,
      days: days,
      dailyMinor: daily,
      spentTodayMinor: spentTodayMinor,
      nextMoney: basis == NextMoneyBasis.rhythm ? nextMoney : null,
      lastsUntil: lastsDays == null
          ? null
          : today.addDays(lastsDays < 0 ? 0 : lastsDays),
    );
  }

  final CalendarDate today;
  final NextMoneyBasis basis;

  /// Day-to-day money at the start of today.
  final int onHandMinor;

  /// Bills set aside before the next money.
  final int billsMinor;
  final int bufferMinor;

  /// Days the daily amount covers, today included.
  final int days;

  /// What can be spent each day until the next money.
  final int dailyMinor;
  final int spentTodayMinor;

  /// When money is next likely, for a steady rhythm.
  final CalendarDate? nextMoney;

  /// The day the money on hand runs out at the usual pace.
  final CalendarDate? lastsUntil;

  /// Today's amount, less what has been spent today; never below zero.
  int get leftTodayMinor {
    final left = dailyMinor - spentTodayMinor;
    return left < 0 ? 0 : left;
  }

  /// What today's spending went over the daily amount by.
  int get overTodayMinor {
    final over = spentTodayMinor - dailyMinor;
    return over < 0 ? 0 : over;
  }
}

int _atLeastOne(int days) => days < 1 ? 1 : days;
