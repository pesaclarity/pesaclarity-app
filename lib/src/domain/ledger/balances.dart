import '../../core/money/money.dart';
import '../enums.dart';
import 'ledger_entry.dart';

/// Accounts that hold savings rather than day-to-day money.
const savingsAccountTypes = {AccountType.sacco, AccountType.moneyMarket};

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
}

/// The balance of [account] just before [at].
///
/// A balance the institution reported in a message wins: the latest one before
/// [at], plus the entries after it. With none before [at], the first one after
/// [at] is walked back. Without any, it is the opening balance plus every entry
/// from the opening date, less transaction costs.
int balanceAt(
  AccountOpening account,
  Iterable<LedgerEntry> entries, {
  required DateTime at,
}) {
  final own = [
    for (final entry in entries)
      if (entry.accountId == account.id &&
          entry.currency == account.currency &&
          !entry.occurredAt.isBefore(account.openingDate))
        entry,
  ]..sort(_chronological);
  int change(LedgerEntry e) => e.signedMinor - e.feeMinor;

  final before = own.where((e) => e.occurredAt.isBefore(at)).toList();
  final anchor = before.lastIndexWhere((e) => e.balanceAfterMinor != null);
  if (anchor >= 0) {
    return before
        .skip(anchor + 1)
        .fold(before[anchor].balanceAfterMinor!, (sum, e) => sum + change(e));
  }
  final after = own.skip(before.length).toList();
  final next = after.indexWhere((e) => e.balanceAfterMinor != null);
  if (next >= 0) {
    return after
        .take(next + 1)
        .fold(after[next].balanceAfterMinor!, (sum, e) => sum - change(e));
  }
  return before.fold(account.openingBalanceMinor, (sum, e) => sum + change(e));
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
