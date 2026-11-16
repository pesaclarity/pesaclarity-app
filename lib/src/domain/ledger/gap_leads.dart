import '../enums.dart';
import '../time/calendar.dart';
import 'balance_check.dart';
import 'balances.dart';
import 'fuliza_debt.dart';
import 'ledger_entry.dart';

/// A message from the account's institution still waiting in Messages to
/// check, with what the reader makes of it.
class WaitingMessage {
  const WaitingMessage({
    required this.id,
    required this.receivedAt,
    this.amountMinor,
    this.direction,
  });

  /// The review item's id.
  final int id;
  final DateTime receivedAt;

  /// The reader's suggested amount and direction; null when it found none.
  final int? amountMinor;
  final TransactionDirection? direction;
}

/// One thing that may explain a [BalanceGap], with what one tap does.
sealed class GapLead {
  const GapLead();

  /// Whether it explains the whole gap on its own.
  bool get exact;
}

/// A waiting message whose suggested amount and direction are the gap's:
/// "Check this message".
class UnreadLead extends GapLead {
  const UnreadLead(this.message, {required this.exact});

  final WaitingMessage message;
  @override
  final bool exact;
}

/// A row on another account (or space) of exactly the gap: "Move it here".
class OtherAccountLead extends GapLead {
  const OtherAccountLead(this.entry, this.fix);

  final LedgerEntry entry;
  final MoveHere fix;
  @override
  bool get exact => true;
}

/// Money in on M-Pesa that M-Pesa may have kept [amountMinor] of to repay
/// Fuliza: "It went to Fuliza".
class FulizaLead extends GapLead {
  const FulizaLead(this.inflow, this.amountMinor);

  final LedgerEntry inflow;
  final int amountMinor;
  @override
  bool get exact => true;
}

/// The same payment twice: "Remove the copy" when that is safe.
class CopyLead extends GapLead {
  const CopyLead(this.hint);

  final GapHint hint;
  @override
  bool get exact => true;
}

/// Everything behind one gap: what may explain it, best first, and what
/// happened on the account around it.
class GapPicture {
  const GapPicture({
    required this.leads,
    required this.around,
    required this.waiting,
    required this.fuliza,
  });

  /// Likely explanations, the likely missing one first.
  final List<GapLead> leads;

  /// The account's entries from the start of the earlier balance's day to
  /// the end of the later one's, oldest first.
  final List<LedgerEntry> around;

  /// Messages from the institution waiting to be checked over those days,
  /// oldest first.
  final List<WaitingMessage> waiting;

  /// Fuliza worked out from balances over those days.
  final List<FulizaAuto> fuliza;
}

/// Puts together what may explain [gap] on [account]: messages still
/// [waiting] (any from the institution), [all] entries on every account,
/// and the Fuliza worked out from M-Pesa's balances.
///
/// Ranked: a waiting message of exactly the gap, a row of exactly the gap
/// on another account, Fuliza keeping part of money in, a payment counted
/// twice, then waiting messages of other amounts in the gap.
GapPicture gapPicture(
  AccountOpening account,
  BalanceGap gap,
  List<LedgerEntry> all, {
  List<WaitingMessage> waiting = const [],
}) {
  final size = gap.gapMinor.abs();
  final out = gap.gapMinor < 0;
  final dayFrom = gap.from.date.startInstant;
  final dayTo = gap.to.date.addDays(1).startInstant;
  bool inDays(DateTime t) => !t.isBefore(dayFrom) && t.isBefore(dayTo);
  bool inGap(DateTime t) =>
      !t.isBefore(gap.from.occurredAt) && !t.isAfter(gap.to.occurredAt);

  final days = [
    for (final w in waiting)
      if (inDays(w.receivedAt)) w,
  ]..sort((a, b) => a.receivedAt.compareTo(b.receivedAt));
  final wanted = out
      ? TransactionDirection.outflow
      : TransactionDirection.inflow;
  final unread = [
    for (final w in days)
      if (w.direction == wanted && w.amountMinor != null)
        (
          w,
          (w.amountMinor! - size).abs() <=
              claimToleranceMinor(account.currency),
        ),
  ];

  final leads = <GapLead>[
    for (final (w, exact) in unread)
      if (exact && inGap(w.receivedAt)) UnreadLead(w, exact: true),
    for (final (w, exact) in unread)
      if (exact && !inGap(w.receivedAt)) UnreadLead(w, exact: true),
    for (final h in gap.hints)
      if (h.fix case final MoveHere fix) OtherAccountLead(h.entries.first, fix),
  ];

  if (account.canOweFuliza && out) {
    for (final e in gap.between) {
      if (e.isInflow &&
          !e.isCorrection &&
          e.kind != TransactionKind.fulizaDraw &&
          e.amountMinor >= size) {
        leads.add(FulizaLead(e, size));
        break;
      }
    }
  }
  for (final h in gap.hints) {
    if (h.cause == GapCause.countedTwice) leads.add(CopyLead(h));
  }
  for (final (w, exact) in unread) {
    if (!exact && inGap(w.receivedAt)) leads.add(UnreadLead(w, exact: false));
  }

  final own = [
    for (final e in all)
      if (e.accountId == account.id &&
          e.currency == account.currency &&
          inDays(e.occurredAt))
        e,
  ]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));
  final auto = account.canOweFuliza
      ? [
          for (final a in WalletWalk.of(account, all).fuliza.auto)
            if (inDays(a.occurredAt)) a,
        ]
      : const <FulizaAuto>[];
  return GapPicture(leads: leads, around: own, waiting: days, fuliza: auto);
}

/// Where money went on one account over a period, beyond what it was
/// spent on: what [whereItWent] adds up.
class MoneyLeaks {
  const MoneyLeaks({
    this.feesMinor = 0,
    this.fulizaMinor = 0,
    this.notExplainedMinor = 0,
  });

  /// Transaction costs and charges.
  final int feesMinor;

  /// Fuliza access fees and daily charges.
  final int fulizaMinor;

  /// Gaps between reported balances that nothing recorded explains.
  final int notExplainedMinor;

  bool get isEmpty =>
      feesMinor == 0 && fulizaMinor == 0 && notExplainedMinor == 0;
}

/// Fees, Fuliza charges and unexplained gaps on [account] whose time is in
/// [month], from [all] entries and the account's [check].
MoneyLeaks whereItWent(
  AccountOpening account,
  List<LedgerEntry> all,
  AccountCheck check, {
  required YearMonth month,
}) {
  final walk = WalletWalk.of(account, all);
  var fees = 0;
  var fuliza = 0;
  for (final e in walk.entries) {
    if (!month.contains(e.date)) continue;
    if (e.kind == TransactionKind.fulizaDraw) {
      fuliza += e.feeMinor;
    } else {
      fees += e.feeMinor;
      if (e.kind == TransactionKind.charge && e.isOutflow) {
        fees += e.amountMinor;
      }
    }
  }
  for (final a in walk.fuliza.auto) {
    if (a.kind == FulizaAutoKind.drawn && month.contains(a.entry.date)) {
      fuliza += a.feeMinor;
    }
  }
  fuliza += walk.fuliza.chargesIn(month);
  var gaps = 0;
  for (final g in check.gaps) {
    if (!g.claimed && month.contains(g.to.date)) gaps += g.gapMinor.abs();
  }
  return MoneyLeaks(
    feesMinor: fees,
    fulizaMinor: fuliza,
    notExplainedMinor: gaps,
  );
}
