import '../time/calendar.dart';

/// Days a rolling plan covers when money has no fixed day: business, gigs.
const rollingPlanDays = 7;

/// The share of money on hand kept back as a buffer, in percent.
const nextMoneyBufferPercent = 10;

/// Days of spending history before the usual day sets the amount.
const usualDayHistoryDays = 14;

/// Days money is spread over while there is too little history to know a
/// usual day.
const newPlanDays = 30;

/// What tells the plan when money comes next.
enum NextMoneyBasis {
  /// A steady rhythm learnt from messages, such as support every 14 days.
  rhythm,

  /// No fixed day: plan a week at a time.
  rolling,

  /// Nothing expected soon: show how long it lasts.
  noDate,
}

/// A bill set aside before the next money.
class BillDue {
  const BillDue({
    required this.name,
    required this.due,
    required this.amountMinor,
  });

  final String name;
  final CalendarDate due;
  final int amountMinor;
}

/// Safe to spend for people without a payday: what is on hand now, less
/// bills due before the next money and a small buffer, spread over the days
/// until the next money, but never more than is usually spent on a day like
/// today. What is over stays spare instead of showing as safe to spend.
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
    this.bills = const [],
    this.pinned = false,
    this.fromUsualDay = false,
    this.fulizaOwedMinor = 0,
  });

  /// Works out today's amount.
  ///
  /// [onHandAtStartMinor] is the day-to-day balance at the start of today,
  /// so spending during the day lowers [leftTodayMinor] but not the daily
  /// amount. [billsMinor] are bills due before the next money (or within
  /// the plan's days). [paceMinor] is the usual daily spending, used to say
  /// how long the money lasts, and [usualTodayMinor] what is usually spent
  /// on a day like today, which caps the daily amount once [historyDays] of
  /// history show it. [bills] itemise [billsMinor]. A [pinnedDailyMinor] is
  /// the daily amount the person chose to make it last, used instead of the
  /// worked-out one.
  factory UntilNextMoney.calculate({
    required CalendarDate today,
    required NextMoneyBasis basis,
    required int onHandAtStartMinor,
    required int billsMinor,
    required int spentTodayMinor,
    required int paceMinor,
    required int usualTodayMinor,
    required int historyDays,
    CalendarDate? nextMoney,
    List<BillDue> bills = const [],
    int? pinnedDailyMinor,
    int fulizaOwedMinor = 0,
  }) {
    final onHand = onHandAtStartMinor < 0 ? 0 : onHandAtStartMinor;
    final buffer = onHand * nextMoneyBufferPercent ~/ 100;
    final usable = onHand - buffer - billsMinor;
    final knowsUsualDay =
        historyDays >= usualDayHistoryDays && usualTodayMinor > 0;
    final planDays = switch (basis) {
      NextMoneyBasis.rhythm when nextMoney != null =>
        today.daysUntil(nextMoney) < 1 ? 1 : today.daysUntil(nextMoney),
      NextMoneyBasis.noDate when paceMinor > 0 => _atLeastOne(
        (onHand - billsMinor) ~/ paceMinor,
      ),
      _ => rollingPlanDays,
    };
    // Without a usual day to go by, a short plan would hand over nearly
    // everything at once: spread it over a month instead.
    final days =
        !knowsUsualDay &&
            basis != NextMoneyBasis.rhythm &&
            planDays < newPlanDays
        ? newPlanDays
        : planDays;
    final affordable = usable <= 0 ? 0 : usable ~/ days;
    final fromUsualDay = knowsUsualDay && usualTodayMinor < affordable;
    final worked = fromUsualDay ? usualTodayMinor : affordable;
    // Nothing is safe to spend once bills and the buffer take it all, or
    // the accounts are below zero: not even an amount chosen earlier.
    final daily = usable <= 0 ? 0 : pinnedDailyMinor ?? worked;
    final lastsDays = paceMinor <= 0
        ? null
        : (onHand - billsMinor) ~/ paceMinor;
    return UntilNextMoney(
      today: today,
      basis: basis,
      onHandMinor: onHandAtStartMinor,
      billsMinor: billsMinor,
      bufferMinor: buffer,
      days: days,
      dailyMinor: daily,
      spentTodayMinor: spentTodayMinor,
      nextMoney: basis == NextMoneyBasis.rhythm ? nextMoney : null,
      lastsUntil: lastsDays == null
          ? null
          : today.addDays(lastsDays < 0 ? 0 : lastsDays),
      bills: bills,
      pinned: pinnedDailyMinor != null && usable > 0,
      fromUsualDay: pinnedDailyMinor == null && fromUsualDay,
      fulizaOwedMinor: fulizaOwedMinor,
    );
  }

  final CalendarDate today;
  final NextMoneyBasis basis;

  /// Day-to-day money at the start of today, Fuliza owed taken off. Below
  /// zero when more is owed than held.
  final int onHandMinor;

  /// Fuliza owed, already taken off [onHandMinor].
  final int fulizaOwedMinor;

  /// Whether bills and the buffer leave nothing to spend, or the accounts
  /// are below zero.
  bool get nothingSafe =>
      onHandMinor <= 0 || onHandMinor - bufferMinor - billsMinor <= 0;

  /// Whether the accounts together are below zero.
  bool get belowZero => onHandMinor < 0;

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

  /// The bills in [billsMinor], soonest first.
  final List<BillDue> bills;

  /// Whether [dailyMinor] is the amount the person chose.
  final bool pinned;

  /// Whether [dailyMinor] is what is usually spent on a day like today,
  /// less than the money would allow.
  final bool fromUsualDay;

  /// The last day the daily amount covers.
  CalendarDate get lastDay => today.addDays(days - 1);

  /// Whether the usual pace would use the money up before [lastDay].
  bool get runsOutEarly =>
      basis != NextMoneyBasis.noDate &&
      lastsUntil != null &&
      lastsUntil!.isBefore(lastDay);

  /// What is left once bills, the buffer and the daily amounts are covered.
  int get spareMinor {
    final spare =
        (onHandMinor < 0 ? 0 : onHandMinor) -
        billsMinor -
        bufferMinor -
        dailyMinor * days;
    return spare < 0 ? 0 : spare;
  }

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
