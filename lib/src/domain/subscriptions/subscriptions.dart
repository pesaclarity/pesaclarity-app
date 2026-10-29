import '../../core/money/money.dart';
import '../enums.dart';
import '../ledger/ledger_entry.dart';
import '../reminders/recurring_charges.dart';
import '../time/calendar.dart';

/// A subscription as saved: tracked, or a suggestion marked as a one-off.
class Subscription {
  Subscription({
    required this.id,
    required this.name,
    required this.amountMinor,
    required this.frequency,
    required this.nextDate,
    this.payeeId,
    String? currency,
    this.status = SubscriptionStatus.tracking,
  }) : currency = currency ?? BaseCurrency.code;

  final int id;
  final String name;
  final int? payeeId;
  final int amountMinor;
  final String currency;
  final RecurrenceFrequency frequency;
  final CalendarDate nextDate;
  final SubscriptionStatus status;
}

/// [date] moved on by one [frequency] step, keeping the day of the month
/// where the month has it.
CalendarDate stepDate(CalendarDate date, RecurrenceFrequency frequency) {
  int months;
  switch (frequency) {
    case RecurrenceFrequency.weekly:
      return date.addDays(7);
    case RecurrenceFrequency.monthly:
      months = 1;
    case RecurrenceFrequency.quarterly:
      months = 3;
    case RecurrenceFrequency.yearly:
      months = 12;
  }
  final month = date.yearMonth.addMonths(months);
  final day = date.day < month.dayCount ? date.day : month.dayCount;
  return CalendarDate(month.year, month.month, day);
}

/// What [amountMinor] charged every [frequency] costs a month.
int monthlyMinor(int amountMinor, RecurrenceFrequency frequency) =>
    switch (frequency) {
      RecurrenceFrequency.weekly => (amountMinor * 52 / 12).round(),
      RecurrenceFrequency.monthly => amountMinor,
      RecurrenceFrequency.quarterly => (amountMinor / 3).round(),
      RecurrenceFrequency.yearly => (amountMinor / 12).round(),
    };

/// A tracked subscription with what the ledger says about it.
class SubscriptionLine {
  const SubscriptionLine({
    required this.subscription,
    required this.amountMinor,
    required this.nextDate,
    this.lastChargedOn,
    this.previousAmountMinor,
  });

  final Subscription subscription;

  /// The latest charge, or the saved amount when none is found.
  final int amountMinor;

  /// The next charge expected on or after today.
  final CalendarDate nextDate;
  final CalendarDate? lastChargedOn;

  /// The charge before the latest, when the price changed.
  final int? previousAmountMinor;

  int get monthlyCostMinor => monthlyMinor(amountMinor, subscription.frequency);
}

/// Every tracked subscription, what they cost, and repeat charges worth
/// tracking.
class SubscriptionsOverview {
  const SubscriptionsOverview({
    required this.lines,
    required this.suggestions,
    required this.currency,
  });

  /// Lines from [saved] and charges in [entries], which should reach back a
  /// year so yearly charges are found. Only lines in [currency] count
  /// towards the totals.
  factory SubscriptionsOverview.of({
    required List<Subscription> saved,
    required Iterable<LedgerEntry> entries,
    required CalendarDate today,
    String? currency,
  }) {
    currency ??= BaseCurrency.code;
    final chargesByPayee = <int, List<LedgerEntry>>{};
    for (final e in entries) {
      if (e.isOutflow && e.payeeId != null) {
        (chargesByPayee[e.payeeId!] ??= []).add(e);
      }
    }

    final lines = <SubscriptionLine>[];
    for (final s in saved) {
      if (s.status != SubscriptionStatus.tracking) continue;
      final charges = [...?chargesByPayee[s.payeeId]]
        ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
      final last = charges.lastOrNull;
      final before = charges.length > 1 ? charges[charges.length - 2] : null;
      var next = last == null ? s.nextDate : stepDate(last.date, s.frequency);
      while (next.isBefore(today)) {
        next = stepDate(next, s.frequency);
      }
      lines.add(
        SubscriptionLine(
          subscription: s,
          amountMinor: last?.amountMinor ?? s.amountMinor,
          nextDate: next,
          lastChargedOn: last?.date,
          previousAmountMinor:
              before != null && before.amountMinor != last!.amountMinor
              ? before.amountMinor
              : null,
        ),
      );
    }
    lines.sort((a, b) => a.nextDate.compareTo(b.nextDate));

    final knownPayees = {for (final s in saved) ?s.payeeId};
    final knownNames = {for (final s in saved) s.name.trim().toLowerCase()};
    final suggestions = [
      for (final charge in detectRecurringCharges(entries, today: today))
        if (!knownPayees.contains(charge.payeeId) &&
            !knownNames.contains(charge.name.trim().toLowerCase()))
          charge,
    ];
    return SubscriptionsOverview(
      lines: lines,
      suggestions: suggestions,
      currency: currency,
    );
  }

  /// Soonest first.
  final List<SubscriptionLine> lines;

  /// Repeat charges not yet tracked or marked as one-offs.
  final List<RecurringCharge> suggestions;
  final String currency;

  int get monthlyTotalMinor => lines
      .where((l) => l.subscription.currency == currency)
      .fold(0, (sum, l) => sum + l.monthlyCostMinor);

  int get yearlyTotalMinor => monthlyTotalMinor * 12;

  SubscriptionLine? get next => lines.firstOrNull;
}
