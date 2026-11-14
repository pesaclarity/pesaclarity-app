import '../enums.dart';
import 'balances.dart';
import 'ledger_entry.dart';

/// Why two reported balances might not add up.
enum GapCause {
  /// The same payment is in twice: from a message and a statement, or two
  /// messages.
  countedTwice,

  /// A payment of exactly the gap is recorded under another account.
  wrongAccount,

  /// A payment recorded the wrong way round would make up the gap.
  wrongDirection,

  /// One side of a move between the person's own accounts is missing here.
  unpairedTransfer,

  /// A Fuliza draw or its fee explains the gap.
  fuliza,

  /// Nothing recorded explains it: probably a message that never arrived.
  missed,

  /// The balance was read or typed while checking a message and does not
  /// follow from the one before, so it is left out.
  doubtfulBalance,
}

/// What one tap can safely do about a gap.
sealed class GapFix {
  const GapFix();
}

/// Removes [entryId], a clear duplicate copy of [keptId].
class RemoveCopy extends GapFix {
  const RemoveCopy(this.entryId, this.keptId);

  final int entryId;
  final int keptId;
}

/// Moves [entryId] onto the account with the gap.
class MoveHere extends GapFix {
  const MoveHere(this.entryId, this.toAccountId);

  final int entryId;
  final int toAccountId;
}

/// One likely reason for a gap, with the entries behind it.
class GapHint {
  const GapHint(this.cause, {this.entries = const [], this.fix});

  final GapCause cause;

  /// The entries the reason is about; empty for [GapCause.missed].
  final List<LedgerEntry> entries;

  /// The safe one-tap fix, or null when only a correction will do.
  final GapFix? fix;
}

/// Two checkpoints on one account whose entries do not add up.
class BalanceGap {
  const BalanceGap({
    required this.accountId,
    required this.from,
    required this.to,
    required this.expectedMinor,
    required this.reportedMinor,
    required this.between,
    required this.hints,
    this.claimed = false,
  });

  final int accountId;

  /// Whether [to] holds a claimed balance (read or typed while checking a
  /// message), which balances leave out, rather than a reported one.
  final bool claimed;

  /// The earlier checkpoint and the later one that does not follow from it.
  final LedgerEntry from;
  final LedgerEntry to;

  /// What the later checkpoint should have said, from the earlier one and
  /// the entries in between.
  final int expectedMinor;
  final int reportedMinor;

  /// The entries after [from] up to and including [to].
  final List<LedgerEntry> between;

  /// Likely reasons, most likely first. Never empty: the last resort is
  /// [GapCause.missed].
  final List<GapHint> hints;

  /// What the account has that the entries do not explain: positive when it
  /// holds more than the entries say.
  int get gapMinor => reportedMinor - expectedMinor;
}

/// Where an account's balance stands against its own messages.
enum BalanceStatus {
  /// Every recent pair of reported balances adds up.
  matches,

  /// The latest reported balance does not follow from the one before.
  off,

  /// Cash: nothing reports it, so it is counted now and then.
  countAgain,

  /// No message has reported a balance yet.
  notReported,
}

/// One account's balance check.
class AccountCheck {
  const AccountCheck({
    required this.account,
    required this.status,
    required this.gaps,
    this.lastReported,
    this.lastCounted,
  });

  final AccountOpening account;
  final BalanceStatus status;

  /// Every gap found, oldest first.
  final List<BalanceGap> gaps;

  /// The newest entry whose message reported a balance.
  final LedgerEntry? lastReported;

  /// When the person last set the balance by hand, or opened the account.
  final DateTime? lastCounted;

  /// The newest gap, which sets the badge.
  BalanceGap? get latestGap => gaps.isEmpty ? null : gaps.last;

  bool get needsALook => gaps.isNotEmpty;
}

/// Walks [account]'s checkpoints in [entries] and finds where two reported
/// balances do not add up, with likely reasons. [entries] may hold every
/// account's: entries on other accounts are looked at for payments that
/// may belong here.
///
/// A gap that ends at a correction is the person's own figure, so it never
/// counts as a gap.
AccountCheck checkAccount(
  AccountOpening account,
  Iterable<LedgerEntry> entries,
) {
  final all = entries.toList();
  final walk = WalletWalk.of(account, all);
  final own = walk.entries;
  final tolerance = claimToleranceMinor(account.currency);

  final gaps = <BalanceGap>[];
  LedgerEntry? previous;
  LedgerEntry? lastReported;
  DateTime? lastCounted = account.openingDate;
  var running = account.openingBalanceMinor;

  List<LedgerEntry> since(LedgerEntry? from, LedgerEntry to) => [
    for (final x in own)
      if (from == null || _chronological(x, from) > 0)
        if (_chronological(x, to) <= 0) x,
  ];

  for (final e in own) {
    if (e.isCorrection && e.balanceAfterMinor != null) {
      lastCounted = e.occurredAt;
    }
    running += walk.change(e) + walk.fundedBy(e);
    final trusted = e.balanceAfterMinor != null;
    final claimed = e.claimedBalanceMinor;
    if (!trusted && claimed == null) continue;
    if (!e.isCorrection) lastReported = e;

    if (trusted) {
      final reported = checkpointWallet(account, e);
      // The first reported balance starts the account; a correction is
      // the person's own figure.
      if (previous != null && !e.isCorrection && reported != running) {
        final between = since(previous, e);
        gaps.add(
          BalanceGap(
            accountId: account.id,
            from: previous,
            to: e,
            expectedMinor: running,
            reportedMinor: reported,
            between: between,
            hints: _hints(
              account,
              walk,
              between,
              all,
              previous,
              e,
              reported - running,
            ),
          ),
        );
      }
      previous = e;
      running = reported;
    } else if ((claimed! - running).abs() > tolerance) {
      // A balance read or typed while checking a message that does not
      // follow: left out of balances, and named here.
      gaps.add(
        BalanceGap(
          accountId: account.id,
          from: previous ?? e,
          to: e,
          expectedMinor: running,
          reportedMinor: claimed,
          between: since(previous, e),
          claimed: true,
          hints: [
            GapHint(GapCause.doubtfulBalance, entries: [e]),
          ],
        ),
      );
    } else {
      previous = e;
      running = claimed;
    }
  }

  final last = lastReported;
  final status = account.type == AccountType.cash && last == null
      ? BalanceStatus.countAgain
      : last == null
      ? BalanceStatus.notReported
      : gaps.isNotEmpty && _chronological(gaps.last.to, last) >= 0
      ? BalanceStatus.off
      : BalanceStatus.matches;
  return AccountCheck(
    account: account,
    status: status,
    gaps: gaps,
    lastReported: last,
    lastCounted: lastCounted,
  );
}

/// Likely reasons for a [gap] between [from] and [to], most likely first.
List<GapHint> _hints(
  AccountOpening account,
  WalletWalk walk,
  List<LedgerEntry> between,
  List<LedgerEntry> all,
  LedgerEntry from,
  LedgerEntry to,
  int gap,
) {
  final hints = <GapHint>[];

  // Counted twice: removing one copy closes the gap.
  for (var i = 0; i < between.length; i++) {
    for (var j = i + 1; j < between.length; j++) {
      final a = between[i];
      final b = between[j];
      if (a.direction != b.direction ||
          a.amountMinor != b.amountMinor ||
          a.date != b.date ||
          a.isCorrection ||
          b.isCorrection) {
        continue;
      }
      final copy = _copyOf(a, b);
      if (walk.change(copy) != -gap) continue;
      final kept = identical(copy, a) ? b : a;
      final clear =
          a.source != b.source ||
          (a.source == TransactionSource.sms &&
              b.source == TransactionSource.sms &&
              a.occurredAt == b.occurredAt &&
              a.kind == b.kind);
      hints.add(
        GapHint(
          GapCause.countedTwice,
          entries: [kept, copy],
          fix: clear && copy.balanceAfterMinor == null
              ? RemoveCopy(copy.id, kept.id)
              : null,
        ),
      );
    }
  }

  // Recorded under another account: moving it here closes the gap.
  for (final e in all) {
    if (e.accountId == account.id ||
        e.currency != account.currency ||
        e.transferPairId != null ||
        e.isCorrection ||
        e.balanceAfterMinor != null ||
        e.occurredAt.isBefore(from.occurredAt) ||
        e.occurredAt.isAfter(to.occurredAt)) {
      continue;
    }
    if (e.signedMinor - e.feeMinor == gap) {
      hints.add(
        GapHint(
          GapCause.wrongAccount,
          entries: [e],
          fix: MoveHere(e.id, account.id),
        ),
      );
    }
  }

  // The wrong way round: flipping it would move the balance twice its size.
  for (final e in between) {
    if (e.isCorrection || identical(e, to)) continue;
    if (-2 * e.signedMinor == gap) {
      hints.add(GapHint(GapCause.wrongDirection, entries: [e]));
    }
  }

  // The other side of a move between own accounts, missing here.
  const slack = Duration(minutes: 30);
  for (final e in all) {
    if (e.accountId == account.id ||
        e.transferPairId != null ||
        e.currency != account.currency ||
        e.isCorrection ||
        e.occurredAt.isBefore(from.occurredAt.subtract(slack)) ||
        e.occurredAt.isAfter(to.occurredAt.add(slack))) {
      continue;
    }
    final transferish =
        e.transferAccountId == account.id ||
        e.categoryType == CategoryType.transfer ||
        e.kind == TransactionKind.bank;
    if (transferish && -e.signedMinor == gap) {
      hints.add(GapHint(GapCause.unpairedTransfer, entries: [e]));
    }
  }

  // Fuliza.
  for (final e in between) {
    if (e.kind != TransactionKind.fulizaDraw &&
        e.kind != TransactionKind.fulizaRepayment) {
      continue;
    }
    final size = gap.abs();
    if (size == e.amountMinor ||
        size == e.feeMinor ||
        size == e.amountMinor + e.feeMinor) {
      hints.add(GapHint(GapCause.fuliza, entries: [e]));
    }
  }

  if (hints.isEmpty) hints.add(const GapHint(GapCause.missed));
  return hints;
}

/// Of two copies of one payment, the one to remove: a statement line or a
/// hand-typed one before a message, one without a reported balance before
/// one with, else the newer.
LedgerEntry _copyOf(LedgerEntry a, LedgerEntry b) {
  int rank(LedgerEntry e) =>
      (e.balanceAfterMinor != null ? 4 : 0) +
      (e.source == TransactionSource.sms ? 2 : 0);
  final byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) return byRank < 0 ? a : b;
  return a.id > b.id ? a : b;
}

int _chronological(LedgerEntry a, LedgerEntry b) {
  final byTime = a.occurredAt.compareTo(b.occurredAt);
  return byTime != 0 ? byTime : a.id.compareTo(b.id);
}
