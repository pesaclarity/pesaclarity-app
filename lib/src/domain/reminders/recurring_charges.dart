import '../../core/money/money.dart';
import '../enums.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../time/calendar.dart';

/// A charge that has come from the same payee once a month, such as a
/// streaming subscription or a card instalment, and when the next one is
/// expected.
class RecurringCharge {
  RecurringCharge({
    required this.name,
    required this.amountMinor,
    required this.lastDate,
    required this.nextDate,
    this.payeeId,
    String? currency,
  }) : currency = currency ?? BaseCurrency.code;

  final String name;
  final int? payeeId;

  /// The latest charge's amount.
  final int amountMinor;
  final String currency;
  final CalendarDate lastDate;
  final CalendarDate nextDate;
}

/// Kinds of payment a merchant can take again without being sent money by
/// hand each time.
const _chargeKinds = {
  TransactionKind.paybill,
  TransactionKind.till,
  TransactionKind.bank,
};

/// Finds payees charged once in each of the last two months, a month apart,
/// for similar amounts, and expects the next charge on the same day next
/// month. Day-to-day spending and money sent to people are left out.
///
/// Only charges expected on or after [today] are returned, soonest first. Two
/// amounts are similar when the smaller is at least 80% of the larger.
List<RecurringCharge> detectRecurringCharges(
  Iterable<LedgerEntry> entries, {
  required CalendarDate today,
}) {
  final byPayee = <String, List<LedgerEntry>>{};
  for (final entry in entries) {
    if (!entry.isOutflow || !_chargeKinds.contains(entry.kind)) continue;
    if (entry.isDailySpending) continue;
    final role = roleOf(entry);
    if (role != LedgerRole.spending && role != LedgerRole.debtRepayment) {
      continue;
    }
    final key = entry.payeeId != null
        ? 'id:${entry.payeeId}'
        : entry.payeeName == null
        ? null
        : 'name:${entry.payeeName!.trim().toLowerCase()}';
    if (key == null) continue;
    (byPayee[key] ??= []).add(entry);
  }

  final charges = <RecurringCharge>[];
  for (final group in byPayee.values) {
    group.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
    final last = group.last;
    final lastDate = last.date;
    final inLastMonth = group.where(
      (e) => e.date.yearMonth == lastDate.yearMonth,
    );
    if (inLastMonth.length > 1) continue;
    LedgerEntry? previous;
    for (final entry in group.reversed.skip(1)) {
      if (entry.date.yearMonth.monthsUntil(lastDate.yearMonth) == 1) {
        previous = entry;
        break;
      }
    }
    if (previous == null || previous.currency != last.currency) continue;

    final gap = previous.date.daysUntil(lastDate);
    if (gap < 25 || gap > 35) continue;
    if (!_similar(previous.amountMinor, last.amountMinor)) continue;

    final nextMonth = lastDate.yearMonth.next;
    final day = lastDate.day < nextMonth.dayCount
        ? lastDate.day
        : nextMonth.dayCount;
    final next = CalendarDate(nextMonth.year, nextMonth.month, day);
    if (next.isBefore(today)) continue;

    charges.add(
      RecurringCharge(
        name: last.payeeName ?? 'A repeating charge',
        payeeId: last.payeeId,
        amountMinor: last.amountMinor,
        currency: last.currency,
        lastDate: lastDate,
        nextDate: next,
      ),
    );
  }
  return charges..sort((a, b) => a.nextDate.compareTo(b.nextDate));
}

bool _similar(int a, int b) {
  final small = a < b ? a : b;
  final large = a < b ? b : a;
  return small * 5 >= large * 4;
}
