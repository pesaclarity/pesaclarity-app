// The balance code as it stood before the journal (decision 0018, stage 1):
// balances worked out by walking each account's entries. The app reads its
// balances from the journal now; these stay as the oracle the journal is
// tested against.
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/journal_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/fuliza_debt.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';

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

/// Accounts whose stored journal balance in [db] just before [at] is not
/// what the oracle works out from the same records: empty when they agree.
Future<List<String>> reconcileWithOracle(
  AppDatabase db, {
  required DateTime at,
}) async {
  final accounts = await DriftAccountsRepository(db).openings();
  final history = await DriftTransactionsRepository(db)
      .ledgerEntries(from: DateTime.utc(1970), to: DateTime.utc(9999));
  final stored = await JournalRepository(db).balances(at: at);
  final off = <String>[];
  for (final a in accounts) {
    void check(BookAccount account, int records) {
      final journal = stored[(account, a.currency)] ?? 0;
      if (journal != records) off.add('$account: $journal, oracle $records');
    }

    check(BookAccount.money(a.id), balanceAt(a, history, at: at));
    if (a.canOweFuliza) {
      check(BookAccount.fulizaOwed(a.id), fulizaOwedAt(a, history, at: at));
    }
  }
  return off;
}

/// [balanceAt] with stage 2's one deliberate change: a Fuliza draw that
/// funded a payment counts with that payment even when the payment's
/// balance was a claim left out (see `postJournal`). [balanceAt] lost such
/// a draw's money altogether.
int balanceWithFundedDrawsAt(
  AccountOpening account,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
}) {
  final walk = WalletWalk.of(account, entries);
  final own = walk.entries;
  int change(LedgerEntry e) => walk.change(e) + walk.fundedBy(e);
  final before = own.where((e) => e.occurredAt.isBefore(at)).toList();
  final anchor = before.lastIndexWhere(walk.isCheckpoint);
  if (anchor >= 0) {
    return before
        .skip(anchor + 1)
        .fold(walk.checkpoints[before[anchor].id]!, (s, e) => s + change(e));
  }
  final after = own.skip(before.length).toList();
  final next = after.indexWhere(walk.isCheckpoint);
  if (next >= 0) {
    return after
        .take(next + 1)
        .fold(walk.checkpoints[after[next].id]!, (s, e) => s - change(e));
  }
  return before.fold(account.openingBalanceMinor, (s, e) => s + change(e));
}
