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

/// One account's entries as balances read them: what each changes the
/// wallet by, and the wallet balance at each checkpoint.
class WalletWalk {
  WalletWalk._(
    this.account,
    this.entries,
    this._funded,
    this._fundedBy,
    this.checkpoints,
  );

  /// Walks [account]'s entries in [all].
  ///
  /// A balance a parser rule or statement reported, or one the person set,
  /// is a checkpoint. A balance the reader found or the person typed while
  /// checking a message is only a claim: it becomes a checkpoint when it is
  /// within [claimToleranceMinor] of the last checkpoint (or the opening
  /// balance) plus the entries since, and is otherwise left out.
  factory WalletWalk.of(AccountOpening account, Iterable<LedgerEntry> all) {
    final own = _ownEntries(account, all);
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
    final walk = WalletWalk._(account, own, funded, fundedBy, {});
    final tolerance = claimToleranceMinor(account.currency);
    var running = account.openingBalanceMinor;
    for (final e in own) {
      running += walk.change(e) + walk.fundedBy(e);
      if (e.balanceAfterMinor != null) {
        running = checkpointWallet(account, e);
        walk.checkpoints[e.id] = running;
      } else if (e.claimedBalanceMinor case final claimed?
          when (claimed - running).abs() <= tolerance) {
        running = claimed;
        walk.checkpoints[e.id] = claimed;
      }
    }
    return walk;
  }

  final AccountOpening account;

  /// The account's own entries from its opening date, oldest first.
  final List<LedgerEntry> entries;
  final Set<int> _funded;
  final Map<int, int> _fundedBy;

  /// Fuliza drawn to fund the payment that reported balance [e]: in that
  /// balance already, though its message came just after.
  int fundedBy(LedgerEntry e) => _fundedBy[e.id] ?? 0;

  /// The wallet balance after each checkpoint, by entry id.
  final Map<int, int> checkpoints;

  /// What [e] changes the wallet by. A Fuliza draw adds its amount, but its
  /// access fee is owed to Fuliza; a draw just after a reported balance
  /// funded the payment that reported it, so it adds nothing.
  int change(LedgerEntry e) {
    if (e.kind == TransactionKind.fulizaDraw) {
      return _funded.contains(e.id) ? 0 : e.signedMinor;
    }
    return e.signedMinor - e.feeMinor;
  }

  bool isCheckpoint(LedgerEntry e) => checkpoints.containsKey(e.id);
}

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

/// Fuliza owed on [account] just before [at], from [FulizaDebt]: the
/// latest total a Fuliza message printed, plus later draws and access
/// fees, less later repayments, never below zero. A correction resets it to
/// what the person said. Zero for accounts that cannot owe Fuliza.
int fulizaOwedAt(
  AccountOpening account,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
}) {
  if (!account.canOweFuliza) return 0;
  return FulizaDebt.of([
    for (final e in _ownEntries(account, entries))
      if (e.occurredAt.isBefore(at)) e,
  ]).owedMinor;
}

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
