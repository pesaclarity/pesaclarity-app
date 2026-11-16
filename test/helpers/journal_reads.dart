// Balances as the app reads them now: from the journal (decision 0018,
// stage 2), posted in memory from the same records. Named as the balance
// functions they replace, so tests written against those read the journal.
import 'package:pesaclarity/src/domain/books/journal_balances.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/domain/ledger/fuliza_debt.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';

import 'balance_oracle.dart' as oracle;

JournalBalances journalOf(
  Iterable<AccountOpening> accounts,
  Iterable<LedgerEntry> entries,
) => JournalBalances.ofRecords(accounts, entries);

/// The wallet of [account] just before [at], from the journal.
int balanceAt(
  AccountOpening account,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
}) => journalOf([account], entries).walletAt(account, at: at);

/// Fuliza owed on [account] just before [at], from the journal.
int fulizaOwedAt(
  AccountOpening account,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
}) => journalOf([account], entries).fulizaOwedAt(account, at: at);

/// The Fuliza debt just before [at]: what is owed from the journal, its due
/// date and charges from Fuliza's messages up to then.
FulizaDebt fulizaDebtAt(
  AccountOpening account,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
}) => oracle
    .fulizaDebtAt(account, entries, at: at)
    .withOwed(fulizaOwedAt(account, entries, at: at));

/// What [account] is worth just before [at], from the journal.
int heldAt(
  AccountOpening account,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
}) => journalOf([account], entries).heldAt(account, at: at);

int totalBalanceAt(
  Iterable<AccountOpening> accounts,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
  required bool Function(AccountOpening account) where,
}) =>
    journalOf(accounts, entries).totalWalletAt(accounts, at: at, where: where);

int totalHeldAt(
  Iterable<AccountOpening> accounts,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
  required bool Function(AccountOpening account) where,
}) => journalOf(accounts, entries).totalHeldAt(accounts, at: at, where: where);
