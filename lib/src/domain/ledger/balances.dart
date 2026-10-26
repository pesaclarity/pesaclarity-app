import '../enums.dart';
import 'ledger_entry.dart';

/// Accounts that hold savings rather than day-to-day money.
const savingsAccountTypes = {AccountType.sacco, AccountType.moneyMarket};

/// What the ledger needs to know to work out an account's balance.
class AccountOpening {
  const AccountOpening({
    required this.id,
    required this.type,
    required this.openingBalanceMinor,
    required this.openingDate,
    this.currency = 'KES',
  });

  final int id;
  final AccountType type;
  final int openingBalanceMinor;

  /// The instant [openingBalanceMinor] was true; earlier entries are ignored.
  final DateTime openingDate;
  final String currency;

  bool get isSavings => savingsAccountTypes.contains(type);
}

/// The balance of [account] just before [at]: its opening balance plus every
/// entry on it from its opening date, less transaction costs.
int balanceAt(
  AccountOpening account,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
}) {
  var balance = account.openingBalanceMinor;
  for (final entry in entries) {
    if (entry.accountId != account.id ||
        entry.currency != account.currency ||
        entry.occurredAt.isBefore(account.openingDate) ||
        !entry.occurredAt.isBefore(at)) {
      continue;
    }
    balance += entry.signedMinor - entry.feeMinor;
  }
  return balance;
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
