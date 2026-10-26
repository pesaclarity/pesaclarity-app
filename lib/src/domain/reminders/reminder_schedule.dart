import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../plan/month_plan.dart';
import '../time/calendar.dart';
import 'recurring_charges.dart';
import 'reminder_settings.dart';

enum ReminderKind { bill, cardCharge, payday, safeToSpend }

/// One local notification to show at [at].
class Reminder {
  const Reminder({
    required this.id,
    required this.kind,
    required this.at,
    required this.title,
    required this.body,
  });

  /// Stable within one schedule; the scheduler replaces all ids each time.
  final int id;
  final ReminderKind kind;

  /// The instant to show it, in UTC.
  final DateTime at;
  final String title;
  final String body;

  @override
  String toString() => 'Reminder($id, ${kind.name}, $at, $title, $body)';
}

/// A dated line from the plan that a reminder can point at.
class DuePayment {
  const DuePayment({
    required this.name,
    required this.amountMinor,
    required this.dueDate,
    this.currency = 'KES',
  });

  final String name;
  final int amountMinor;
  final String currency;
  final CalendarDate dueDate;
}

/// Unpaid bills and expected paydays with a due date in [review]'s month.
///
/// Bills are lines in bill categories (see [MonthPlan.isBillCategory]) that
/// are not paid yet; paydays are income lines.
({List<DuePayment> bills, List<DuePayment> paydays}) duePaymentsIn(
  MonthReview review,
) {
  final plan = review.plan;
  final bills = <DuePayment>[];
  for (final category in review.categories) {
    for (final progress in category.lines) {
      final line = progress.line;
      final due = line.dueDate;
      if (due == null || progress.isPaid) continue;
      if (!plan.isBillCategory(line.categoryId)) continue;
      bills.add(
        DuePayment(
          name: line.name,
          amountMinor: progress.unpaidMinor,
          dueDate: due,
        ),
      );
    }
  }
  final paydays = [
    for (final line in plan.incomeLines)
      if (line.dueDate != null)
        DuePayment(
          name: line.name,
          amountMinor: line.amountMinor,
          dueDate: line.dueDate!,
        ),
  ];
  return (bills: bills, paydays: paydays);
}

/// Works out every notification to schedule from [now] on.
///
/// Bills and card charges are reminded [ReminderSettings.leadDays] before
/// they are due, at [ReminderSettings.dueReminderMinuteOfDay]; when that time
/// has passed but the due date has not, the reminder moves to the next such
/// time up to the due date. Paydays are reminded on the day. The daily
/// safe-to-spend notification covers the next [dailyDays] days; only today's
/// carries an amount, since later days depend on spending not yet made.
///
/// With [showAmounts] false no notification text contains an amount, so the
/// lock screen shows none. At most [limit] reminders are returned, soonest
/// first.
List<Reminder> planReminders({
  required ReminderSettings settings,
  required DateTime now,
  List<DuePayment> bills = const [],
  List<DuePayment> paydays = const [],
  List<RecurringCharge> charges = const [],
  int? safeToSpendTodayMinor,
  String currency = 'KES',
  bool showAmounts = true,
  int dailyDays = 7,
  int limit = 60,
}) {
  if (!settings.enabled) return const [];
  final today = CalendarDate.nairobi(now);
  final drafts = <_Draft>[];

  DateTime atMinute(CalendarDate date, int minuteOfDay) =>
      date.startInstant.add(Duration(minutes: minuteOfDay));

  DateTime? dueReminderTime(CalendarDate due, int leadDays) {
    const minute = ReminderSettings.dueReminderMinuteOfDay;
    var date = due.addDays(-leadDays);
    if (date.isBefore(today)) date = today;
    var at = atMinute(date, minute);
    if (!at.isAfter(now)) {
      date = date.addDays(1);
      at = atMinute(date, minute);
    }
    return date.isAfter(due) ? null : at;
  }

  String amount(int minor, String code) =>
      formatMoney(Money(minor, currency: code));

  if (settings.bills) {
    for (final bill in bills) {
      final at = dueReminderTime(bill.dueDate, settings.leadDays);
      if (at == null) continue;
      final when = _whenDue(CalendarDate.nairobi(at), bill.dueDate);
      drafts.add(
        _Draft(
          ReminderKind.bill,
          at,
          '${bill.name} is due $when',
          showAmounts
              ? 'Pay ${amount(bill.amountMinor, bill.currency)} by '
                    '${formatShortDate(bill.dueDate)}.'
              : 'Due ${formatShortDate(bill.dueDate)}. Open your plan to see '
                    'the amount.',
        ),
      );
    }
  }

  if (settings.cardCharges) {
    for (final charge in charges) {
      final at = dueReminderTime(charge.nextDate, settings.leadDays);
      if (at == null) continue;
      final when = _whenDue(CalendarDate.nairobi(at), charge.nextDate);
      drafts.add(
        _Draft(
          ReminderKind.cardCharge,
          at,
          '${charge.name} charges $when',
          showAmounts
              ? 'Expect about ${amount(charge.amountMinor, charge.currency)} '
                    'on ${formatShortDate(charge.nextDate)}, like last month.'
              : 'Expected on ${formatShortDate(charge.nextDate)}, like last '
                    'month.',
        ),
      );
    }
  }

  if (settings.payday) {
    for (final payday in paydays) {
      final at = dueReminderTime(payday.dueDate, 0);
      if (at == null) continue;
      drafts.add(
        _Draft(
          ReminderKind.payday,
          at,
          'Payday: ${payday.name}',
          'Split your pay now: bills and debts first, then savings.',
        ),
      );
    }
  }

  if (settings.dailySafeToSpend) {
    for (var offset = 0; offset < dailyDays; offset++) {
      final date = today.addDays(offset);
      final at = atMinute(date, settings.dailyMinuteOfDay);
      if (!at.isAfter(now)) continue;
      final figure = offset == 0 ? safeToSpendTodayMinor : null;
      drafts.add(
        _Draft(
          ReminderKind.safeToSpend,
          at,
          'Safe to spend today',
          showAmounts && figure != null
              ? '${amount(figure < 0 ? 0 : figure, currency)} for today.'
              : 'See what you can spend today.',
        ),
      );
    }
  }

  drafts.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.kind.index.compareTo(b.kind.index);
  });
  return [
    for (final (index, draft) in drafts.take(limit).indexed)
      Reminder(
        id: index + 1,
        kind: draft.kind,
        at: draft.at.toUtc(),
        title: draft.title,
        body: draft.body,
      ),
  ];
}

class _Draft {
  const _Draft(this.kind, this.at, this.title, this.body);

  final ReminderKind kind;
  final DateTime at;
  final String title;
  final String body;
}

String _whenDue(CalendarDate on, CalendarDate due) {
  final days = on.daysUntil(due);
  return switch (days) {
    0 => 'today',
    1 => 'tomorrow',
    _ => 'in $days days',
  };
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// A date as reminders show it, such as `Sun 1 Nov`.
String formatShortDate(CalendarDate date) =>
    '${_weekdays[date.weekday - 1]} ${date.day} ${_months[date.month - 1]}';
