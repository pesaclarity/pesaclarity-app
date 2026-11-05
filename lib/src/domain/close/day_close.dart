import '../ledger/balances.dart';
import '../ledger/ledger_entry.dart';
import '../time/calendar.dart';

/// What the drawer should hold at the end of a day: cash at the start, plus
/// cash in, less cash out.
class DayCash {
  const DayCash({
    required this.startMinor,
    required this.inMinor,
    required this.outMinor,
  });

  final int startMinor;
  final int inMinor;

  /// Including transaction costs.
  final int outMinor;

  int get expectedMinor => startMinor + inMinor - outMinor;
}

/// The drawer on [day], from the [cash] accounts' [entries].
DayCash dayCash(
  Iterable<AccountOpening> cash,
  Iterable<LedgerEntry> entries, {
  required CalendarDate day,
}) {
  final accounts = cash.toList();
  final ids = {for (final a in accounts) a.id};
  final list = entries.toList();
  final start = day.startInstant;
  final end = day.addDays(1).startInstant;
  var inMinor = 0;
  var outMinor = 0;
  for (final e in list) {
    if (!ids.contains(e.accountId) ||
        e.occurredAt.isBefore(start) ||
        !e.occurredAt.isBefore(end)) {
      continue;
    }
    if (e.isInflow) {
      inMinor += e.amountMinor;
    } else {
      outMinor += e.amountMinor;
    }
    outMinor += e.feeMinor;
  }
  return DayCash(
    startMinor: totalBalanceAt(accounts, list, at: start, where: (_) => true),
    inMinor: inMinor,
    outMinor: outMinor,
  );
}
