import '../enums.dart';
import '../time/calendar.dart';
import 'ledger_entry.dart';

/// Fuliza draws, repayments and the fees hidden in the repayments.
///
/// Fuliza fees are repayments minus draws. Each repayment first clears the
/// draws still outstanding and only the excess is a fee, dated on the
/// repayment. Over a full draw-and-repay cycle the fees
/// equal repayments minus draws, and a draw on the 30th repaid on the 2nd
/// never shows a negative fee in either month.
///
/// A repayment for a draw older than the ledger looks like a fee; the 90-day
/// first scan keeps this to the very start of the history.
class FulizaLedger {
  FulizaLedger._(this._feeByRepaymentId, this.outstandingMinor);

  /// Works through [entries] in time order. Entries other than Fuliza draws
  /// and repayments are ignored.
  factory FulizaLedger.of(Iterable<LedgerEntry> entries) {
    final fuliza =
        entries
            .where(
              (e) =>
                  e.kind == TransactionKind.fulizaDraw ||
                  e.kind == TransactionKind.fulizaRepayment,
            )
            .toList()
          ..sort(_chronological);

    final fees = <int, int>{};
    var outstanding = 0;
    for (final entry in fuliza) {
      if (entry.kind == TransactionKind.fulizaDraw) {
        outstanding += entry.amountMinor;
      } else {
        final principal = entry.amountMinor < outstanding
            ? entry.amountMinor
            : outstanding;
        outstanding -= principal;
        fees[entry.id] = entry.amountMinor - principal;
      }
    }
    return FulizaLedger._(fees, outstanding);
  }

  final Map<int, int> _feeByRepaymentId;

  /// Draws not yet repaid at the end of the entries.
  final int outstandingMinor;

  /// The fee share of a repayment; zero for anything else.
  int feeOf(LedgerEntry entry) => _feeByRepaymentId[entry.id] ?? 0;

  /// Draws, repayments and fees whose Nairobi date falls in [month].
  FulizaMonth month(Iterable<LedgerEntry> entries, YearMonth month) {
    var draws = 0;
    var drawCount = 0;
    var repayments = 0;
    var fees = 0;
    for (final entry in entries) {
      if (!month.contains(entry.date)) continue;
      if (entry.kind == TransactionKind.fulizaDraw) {
        draws += entry.amountMinor;
        drawCount++;
      } else if (entry.kind == TransactionKind.fulizaRepayment) {
        repayments += entry.amountMinor;
        fees += feeOf(entry);
      }
    }
    return FulizaMonth(
      month: month,
      drawsMinor: draws,
      drawCount: drawCount,
      repaymentsMinor: repayments,
      feesMinor: fees,
    );
  }
}

/// One month of Fuliza use.
class FulizaMonth {
  const FulizaMonth({
    required this.month,
    required this.drawsMinor,
    required this.drawCount,
    required this.repaymentsMinor,
    required this.feesMinor,
  });

  final YearMonth month;
  final int drawsMinor;
  final int drawCount;
  final int repaymentsMinor;
  final int feesMinor;
}

/// Oldest first; at the same instant draws come before repayments, then by id.
int _chronological(LedgerEntry a, LedgerEntry b) {
  final byTime = a.occurredAt.compareTo(b.occurredAt);
  if (byTime != 0) return byTime;
  final byKind = (a.kind == TransactionKind.fulizaDraw ? 0 : 1).compareTo(
    b.kind == TransactionKind.fulizaDraw ? 0 : 1,
  );
  if (byKind != 0) return byKind;
  return a.id.compareTo(b.id);
}
