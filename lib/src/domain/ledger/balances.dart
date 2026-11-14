import '../../core/money/money.dart';
import '../enums.dart';
import 'fuliza_debt.dart';
import 'ledger_entry.dart';

/// Accounts that hold savings rather than day-to-day money.
const savingsAccountTypes = {AccountType.sacco, AccountType.moneyMarket};

/// A Fuliza draw this soon after a reported balance funded the payment that
/// reported it, so that balance already holds the draw.
const fulizaFundedWithin = Duration(minutes: 10);

/// What the ledger needs to know to work out an account's balance.
class AccountOpening {
  AccountOpening({
    required this.id,
    required this.type,
    required this.openingBalanceMinor,
    required this.openingDate,
    String? currency,
  }) : currency = currency ?? BaseCurrency.code;

  final int id;
  final AccountType type;
  final int openingBalanceMinor;

  /// The instant [openingBalanceMinor] was true; earlier entries are ignored.
  final DateTime openingDate;
  final String currency;

  bool get isSavings => savingsAccountTypes.contains(type);

  /// Whether the account can owe Fuliza: M-Pesa.
  bool get canOweFuliza => type == AccountType.mpesa;
}

/// [account]'s own entries from its opening date, oldest first.
List<LedgerEntry> _ownEntries(
  AccountOpening account,
  Iterable<LedgerEntry> entries,
) => [
  for (final entry in entries)
    if (entry.accountId == account.id &&
        entry.currency == account.currency &&
        !entry.occurredAt.isBefore(account.openingDate))
      entry,
]..sort(_chronological);

/// How far a claimed balance may be from what the entries add up to and
/// still be used: one unit of the currency.
int claimToleranceMinor(String currency) {
  var minor = 1;
  for (var i = 0; i < minorUnitDigits(currency); i++) {
    minor *= 10;
  }
  return minor;
}

/// The wallet balance a trusted checkpoint states. A correction on an
/// account that can owe Fuliza holds what the person said the account is
/// worth: below zero, the wallet is empty and the rest is Fuliza owed.
int checkpointWallet(AccountOpening account, LedgerEntry checkpoint) {
  final stated = checkpoint.balanceAfterMinor!;
  if (checkpoint.isCorrection && account.canOweFuliza && stated < 0) return 0;
  return stated;
}

/// How far apart a Fuliza repayment message and the incoming money it was
/// taken from can be and still be one event.
const fulizaRepaidWithin = Duration(minutes: 30);

/// One account's entries as balances read them: what each changes the
/// wallet by, the wallet balance at each checkpoint and, for M-Pesa, the
/// Fuliza debt.
class WalletWalk {
  WalletWalk._(
    this.account,
    this.entries,
    this._funded,
    this._fundedBy,
    this._adjust,
    this.checkpoints,
  );

  /// Walks [account]'s entries in [all].
  ///
  /// A balance a parser rule or statement reported, or one the person set,
  /// is a checkpoint. A balance the reader found or the person typed while
  /// checking a message is only a claim: it becomes a checkpoint when it is
  /// within [claimToleranceMinor] of the last checkpoint (or the opening
  /// balance) plus the entries since, and is otherwise left out.
  ///
  /// On M-Pesa the walk also keeps the Fuliza debt ([fuliza]), and reads
  /// what M-Pesa's balances show Fuliza did:
  ///
  /// * Money in while Fuliza is owed, whose balance is lower than the
  ///   wallet plus the amount: M-Pesa kept the difference to repay Fuliza
  ///   (up to what is owed, plus daily charges when the wallet is left with
  ///   money). Its repayment message, when read too, is the same event.
  /// * A payment that leaves the wallet at 0 though it took more than the
  ///   wallet held, with no Fuliza draw message: Fuliza covered the rest,
  ///   plus its 1% access fee.
  /// * Any reported balance above 0: M-Pesa only credits the wallet once
  ///   Fuliza is clear, so nothing is owed after it.
  factory WalletWalk.of(AccountOpening account, Iterable<LedgerEntry> all) {
    final own = _ownEntries(account, all);
    final fuliza = account.canOweFuliza;
    final funded = <int>{};
    final fundedBy = <int, int>{};
    LedgerEntry? lastReported;
    for (final e in own) {
      if (e.kind == TransactionKind.fulizaDraw &&
          lastReported != null &&
          e.occurredAt.difference(lastReported.occurredAt) <=
              fulizaFundedWithin) {
        funded.add(e.id);
        fundedBy.update(
          lastReported.id,
          (sum) => sum + e.signedMinor,
          ifAbsent: () => e.signedMinor,
        );
      }
      if (e.balanceAfterMinor != null || e.claimedBalanceMinor != null) {
        lastReported = e;
      }
    }

    // A repayment message prints the balance after the money it was taken
    // from, so both messages show the same balance: one event.
    final repaidBy = <int, LedgerEntry>{};
    final repaying = <int, LedgerEntry>{};
    if (fuliza) {
      for (final r in own) {
        if (r.kind != TransactionKind.fulizaRepayment) continue;
        final balance = r.balanceAfterMinor ?? r.claimedBalanceMinor;
        if (balance == null) continue;
        LedgerEntry? best;
        for (final i in own) {
          if (!_mayRepayFuliza(i) ||
              i.balanceAfterMinor != balance ||
              repaidBy.containsKey(i.id)) {
            continue;
          }
          final apart = i.occurredAt.difference(r.occurredAt).abs();
          if (apart > fulizaRepaidWithin) continue;
          if (best == null ||
              apart < best.occurredAt.difference(r.occurredAt).abs()) {
            best = i;
          }
        }
        if (best != null) {
          repaidBy[best.id] = r;
          repaying[r.id] = best;
        }
      }
    }

    final adjust = <int, int>{};
    final walk = WalletWalk._(account, own, funded, fundedBy, adjust, {});
    final tolerance = claimToleranceMinor(account.currency);
    final book = FulizaBook();
    final done = <int>{};
    LedgerEntry? lastRepayment;
    // Whether the wallet is known yet: a reported balance came before.
    var known = false;
    var running = account.openingBalanceMinor;
    for (final e in own) {
      var reported = e.balanceAfterMinor;
      if (fuliza) {
        if (e.kind == TransactionKind.fulizaDraw) {
          // A draw whose message came just after a repayment that already
          // covered its total was cleared by that repayment.
          final r = lastRepayment;
          final total = e.owedAfterMinor;
          final alreadyRepaid =
              r != null &&
              total != null &&
              !funded.contains(e.id) &&
              e.occurredAt.difference(r.occurredAt) <= fulizaRepaidWithin &&
              total <= r.amountMinor + tolerance;
          if (!alreadyRepaid) book.draw(e);
        } else if (e.kind == TransactionKind.fulizaRepayment) {
          lastRepayment = e;
          final inflow = repaying[e.id];
          if (inflow == null) {
            book.repay(e.amountMinor, e.date);
          } else {
            // Counted with the money it came from.
            adjust[e.id] = e.amountMinor;
            // Before that money, its balance is not yet true.
            if (!done.contains(inflow.id)) reported = null;
          }
        }
      }
      var delta = walk._base(e) + walk.fundedBy(e) + (adjust[e.id] ?? 0);
      if (fuliza && !e.isCorrection && e.balanceAfterMinor != null) {
        final balance = e.balanceAfterMinor!;
        final expected = running + delta;
        if (_mayRepayFuliza(e)) {
          final r = repaidBy[e.id];
          if (r != null) {
            book.repay(r.amountMinor, r.date);
            lastRepayment = r;
            adjust[e.id] = -r.amountMinor;
            delta -= r.amountMinor;
          } else if (book.owedMinor > 0 && expected - balance > 0) {
            final owed = book.owedMinor;
            final allowance = balance > 0 ? book.chargeAllowance(e.date) : 0;
            final short = expected - balance;
            final paid = short < owed + allowance ? short : owed + allowance;
            final charges = paid > owed ? paid - owed : 0;
            book.repaidFrom(e, paid, charges);
            adjust[e.id] = -paid;
            delta -= paid;
          }
        } else if (e.isOutflow &&
            known &&
            balance == 0 &&
            expected < 0 &&
            walk.fundedBy(e) == 0 &&
            !_drawFollows(e, own) &&
            e.kind != TransactionKind.fulizaRepayment) {
          book.drawnFor(e, -expected);
          adjust[e.id] = -expected;
          delta -= expected;
        }
        done.add(e.id);
      }
      running += delta;
      if (reported != null) {
        running = checkpointWallet(account, e);
        walk.checkpoints[e.id] = running;
        known = true;
        if (fuliza) {
          if (e.isCorrection) {
            book.correction(e);
          } else if (running > 0 &&
              e.kind != TransactionKind.fulizaDraw &&
              !_repaymentFollows(e, own, repaying)) {
            book.walletHasMoney(e);
          }
        }
      } else if (e.claimedBalanceMinor case final claimed?
          when e.balanceAfterMinor == null &&
              (claimed - running).abs() <= tolerance) {
        running = claimed;
        walk.checkpoints[e.id] = claimed;
        known = true;
      }
    }
    walk.fuliza = book.result();
    return walk;
  }

  final AccountOpening account;

  /// The account's own entries from its opening date, oldest first.
  final List<LedgerEntry> entries;
  final Set<int> _funded;
  final Map<int, int> _fundedBy;

  /// What Fuliza changed an entry's effect on the wallet by.
  final Map<int, int> _adjust;

  /// Fuliza drawn to fund the payment that reported balance [e]: in that
  /// balance already, though its message came just after.
  int fundedBy(LedgerEntry e) => _fundedBy[e.id] ?? 0;

  /// The wallet balance after each checkpoint, by entry id.
  final Map<int, int> checkpoints;

  /// The Fuliza debt after the entries; nothing for other accounts.
  late final FulizaDebt fuliza;

  int _base(LedgerEntry e) {
    if (e.kind == TransactionKind.fulizaDraw) {
      return _funded.contains(e.id) ? 0 : e.signedMinor;
    }
    return e.signedMinor - e.feeMinor;
  }

  /// What [e] changes the wallet by. A Fuliza draw adds its amount, but its
  /// access fee is owed to Fuliza; a draw just after a reported balance
  /// funded the payment that reported it, so it adds nothing. Money in that
  /// M-Pesa kept for Fuliza adds only what reached the wallet, and a payment
  /// Fuliza covered takes only what the wallet held.
  int change(LedgerEntry e) => _base(e) + (_adjust[e.id] ?? 0);

  bool isCheckpoint(LedgerEntry e) => checkpoints.containsKey(e.id);
}

/// Money in that M-Pesa would use to repay Fuliza first.
bool _mayRepayFuliza(LedgerEntry e) =>
    e.isInflow &&
    !e.isCorrection &&
    e.kind != TransactionKind.fulizaDraw &&
    e.kind != TransactionKind.fulizaRepayment;

/// Whether a repayment message of its own comes just after [e], as on a
/// statement, where the money in shows the balance before the repayment.
bool _repaymentFollows(
  LedgerEntry e,
  List<LedgerEntry> own,
  Map<int, LedgerEntry> repaying,
) => own.any(
  (r) =>
      r.kind == TransactionKind.fulizaRepayment &&
      !repaying.containsKey(r.id) &&
      _chronological(r, e) > 0 &&
      r.occurredAt.difference(e.occurredAt) <= fulizaRepaidWithin,
);

/// Whether a Fuliza draw message came just after [e], funding it.
bool _drawFollows(LedgerEntry e, List<LedgerEntry> own) => own.any(
  (d) =>
      d.kind == TransactionKind.fulizaDraw &&
      !d.occurredAt.isBefore(e.occurredAt) &&
      d.occurredAt.difference(e.occurredAt) <= fulizaFundedWithin,
);

/// The balance of [account]'s wallet just before [at]: for M-Pesa, the
/// money in it, before any Fuliza owed (see [heldAt]).
///
/// A checkpoint (see [WalletWalk.of]) wins: the latest one before [at],
/// plus the entries after it. With none before [at], the first one after
/// [at] is walked back. Without any, it is the opening balance plus every
/// entry from the opening date, less transaction costs.
int balanceAt(
  AccountOpening account,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
}) {
  final walk = WalletWalk.of(account, entries);
  final own = walk.entries;
  final change = walk.change;

  final before = own.where((e) => e.occurredAt.isBefore(at)).toList();
  final anchor = before.lastIndexWhere(walk.isCheckpoint);
  if (anchor >= 0) {
    return before
        .skip(anchor + 1)
        .fold(
          walk.checkpoints[before[anchor].id]!,
          (sum, e) => sum + change(e),
        );
  }
  final after = own.skip(before.length).toList();
  final next = after.indexWhere(walk.isCheckpoint);
  if (next >= 0) {
    return after
        .take(next + 1)
        .fold(walk.checkpoints[after[next].id]!, (sum, e) => sum - change(e));
  }
  return before.fold(account.openingBalanceMinor, (sum, e) => sum + change(e));
}

/// Fuliza owed on [account] just before [at] (see [fulizaDebtAt]).
int fulizaOwedAt(
  AccountOpening account,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
}) {
  if (!account.canOweFuliza) return 0;
  return fulizaDebtAt(account, entries, at: at).owedMinor;
}

/// The Fuliza debt on [account] just before [at], from [WalletWalk]: the
/// latest total a Fuliza message printed, plus later draws and access
/// fees, less later repayments, never below zero; cleared by any balance
/// above 0 M-Pesa reports after it. A correction resets it to what the
/// person said. Nothing for accounts that cannot owe Fuliza.
FulizaDebt fulizaDebtAt(
  AccountOpening account,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
}) => WalletWalk.of(account, [
  for (final e in entries)
    if (e.occurredAt.isBefore(at)) e,
]).fuliza;

/// What [account] is really worth just before [at]: its wallet less any
/// Fuliza owed. This is the figure Balances and On hand show.
int heldAt(
  AccountOpening account,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
}) {
  final list = entries is List<LedgerEntry> ? entries : entries.toList();
  return balanceAt(account, list, at: at) - fulizaOwedAt(account, list, at: at);
}

int _chronological(LedgerEntry a, LedgerEntry b) {
  final byTime = a.occurredAt.compareTo(b.occurredAt);
  return byTime != 0 ? byTime : a.id.compareTo(b.id);
}

/// The combined balance just before [at] of the [accounts] that pass [where].
int totalBalanceAt(
  Iterable<AccountOpening> accounts,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
  required bool Function(AccountOpening account) where,
}) {
  final list = entries.toList();
  return accounts
      .where(where)
      .fold(0, (sum, a) => sum + balanceAt(a, list, at: at));
}

/// What the [accounts] that pass [where] are really worth just before
/// [at], Fuliza owed taken off (see [heldAt]).
int totalHeldAt(
  Iterable<AccountOpening> accounts,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
  required bool Function(AccountOpening account) where,
}) {
  final list = entries.toList();
  return accounts
      .where(where)
      .fold(0, (sum, a) => sum + heldAt(a, list, at: at));
}
