import '../enums.dart';
import '../time/calendar.dart';
import 'fuliza.dart';
import 'ledger_entry.dart';

/// One day's Fuliza daily charge, worked out from what two Fuliza messages
/// said was owed. Not a transaction: a fee on the Fuliza debt, never taken
/// from the wallet and never a correction.
class FulizaDailyCharge {
  const FulizaDailyCharge(this.date, this.amountMinor);

  final CalendarDate date;
  final int amountMinor;

  @override
  bool operator ==(Object other) =>
      other is FulizaDailyCharge &&
      other.date == date &&
      other.amountMinor == amountMinor;

  @override
  int get hashCode => Object.hash(date, amountMinor);

  @override
  String toString() => 'FulizaDailyCharge($date, $amountMinor)';
}

/// The Fuliza debt as the owner's model has it: a draw starts on its day
/// owing its amount and access fee, a daily charge adds to it every day
/// after until it is repaid, and repayments come off it.
///
/// Each draw message prints the total owed after it. That total is a
/// checkpoint: what it holds beyond the previous total plus the draws,
/// access fees and repayments since is daily charges, spread evenly over
/// the days between the two messages (one charge a day, any remainder on
/// the last day). Before the first checkpoint, or after a repayment clears
/// the debt, there is nothing to spread from, so no charge is made up. After
/// the latest checkpoint nothing is added: the debt is the latest total,
/// plus later draws and fees, less later repayments.
class FulizaDebt {
  FulizaDebt._(this.owedMinor, this.dueAt, this.charges);

  /// Reads Fuliza draws, repayments and corrections in [entries]: pass one
  /// M-Pesa account's.
  factory FulizaDebt.of(Iterable<LedgerEntry> entries) {
    final list =
        entries
            .where(
              (e) =>
                  e.kind == TransactionKind.fulizaDraw ||
                  e.kind == TransactionKind.fulizaRepayment ||
                  (e.isCorrection && e.balanceAfterMinor != null),
            )
            .toList()
          ..sort(compareFulizaEntries);

    var owed = 0;
    DateTime? dueAt;
    CalendarDate? known;
    final charges = <FulizaDailyCharge>[];
    for (final e in list) {
      if (e.isCorrection) {
        final stated = e.balanceAfterMinor!;
        owed = stated < 0 ? -stated : 0;
        known = e.date;
      } else if (e.kind == TransactionKind.fulizaDraw) {
        owed += e.amountMinor + e.feeMinor;
        final total = e.owedAfterMinor;
        if (total != null) {
          final extra = total - owed;
          final since = known;
          if (extra > 0 && since != null) {
            charges.addAll(_spread(extra, since, e.date));
          }
          owed = total;
          known = e.date;
        }
        dueAt = e.owedDueAt ?? dueAt;
      } else {
        if (e.amountMinor >= owed) {
          owed = 0;
          dueAt = null;
          // Cleared: the next draw starts afresh.
          known = e.date;
        } else {
          owed -= e.amountMinor;
        }
      }
    }
    return FulizaDebt._(owed, owed == 0 ? null : dueAt, charges);
  }

  /// Fuliza owed after the last entry.
  final int owedMinor;

  /// When [owedMinor] is due, as the last message said.
  final DateTime? dueAt;

  /// Daily charges worked out between messages, oldest first.
  final List<FulizaDailyCharge> charges;

  /// Daily charges on days in [month].
  int chargesIn(YearMonth month) => charges
      .where((c) => month.contains(c.date))
      .fold(0, (sum, c) => sum + c.amountMinor);
}

/// [extra] spread over the days after [from] up to and including [to]; all
/// on [to] when they are the same day.
List<FulizaDailyCharge> _spread(int extra, CalendarDate from, CalendarDate to) {
  final days = from.daysUntil(to);
  if (days <= 0) return [FulizaDailyCharge(to, extra)];
  final each = extra ~/ days;
  final rest = extra - each * days;
  return [
    for (var d = 1; d <= days; d++)
      FulizaDailyCharge(from.addDays(d), each + (d == days ? rest : 0)),
  ];
}
