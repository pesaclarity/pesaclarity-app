import '../ledger/balances.dart';
import '../ledger/ledger_entry.dart';
import 'book_account.dart';
import 'books.dart';
import 'journal.dart';

/// Balances read from a space's journal (decision 0018, stage 2): every
/// figure is a sum of postings. Built from the stored journal in the app,
/// or from the records with [JournalBalances.ofRecords].
class JournalBalances {
  /// Reads [entries], in any order.
  JournalBalances(Iterable<JournalEntry> entries) {
    for (final e in entries) {
      for (final l in e.lines) {
        (_lines[(l.account, e.currency)] ??= []).add((e.at, l.amountMinor));
      }
    }
    for (final list in _lines.values) {
      list.sort((a, b) => a.$1.compareTo(b.$1));
      var sum = 0;
      final sums = <int>[];
      for (final (_, amount) in list) {
        sums.add(sum += amount);
      }
      _running[list] = sums;
    }
  }

  /// The journal [postJournal] makes of the records, without storing it.
  factory JournalBalances.ofRecords(
    Iterable<AccountOpening> accounts,
    Iterable<LedgerEntry> history, {
    Map<int, BookCategory> categories = const {},
  }) => JournalBalances(
    postJournal(accounts: accounts, history: history, categories: categories),
  );

  final _lines = <(BookAccount, String), List<(DateTime, int)>>{};
  final _running = Expando<List<int>>();

  /// Debit-positive total of [account] in [currency] from postings dated
  /// before [at], or all of them.
  int _debits(BookAccount account, String currency, DateTime? at) {
    final list = _lines[(account, currency)];
    if (list == null || list.isEmpty) return 0;
    final sums = _running[list]!;
    if (at == null) return sums.last;
    // The last posting dated before [at].
    var lo = 0;
    var hi = list.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].$1.isBefore(at)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo == 0 ? 0 : sums[lo - 1];
  }

  /// [account]'s balance in [currency] just before [at] (or after every
  /// posting), positive in its normal direction: what an asset holds, what
  /// is owed, what was earned or spent.
  int balanceOf(BookAccount account, {required String currency, DateTime? at}) {
    final debits = _debits(account, currency, at);
    return account.debitNormal ? debits : -debits;
  }

  /// What [account] moved by in `[from, to)`, in its normal direction.
  int flowOf(
    BookAccount account, {
    required String currency,
    required DateTime from,
    required DateTime to,
  }) =>
      balanceOf(account, currency: currency, at: to) -
      balanceOf(account, currency: currency, at: from);

  /// The money in [account] just before [at]: for M-Pesa, the wallet,
  /// before any Fuliza owed.
  int walletAt(AccountOpening account, {required DateTime at}) => balanceOf(
    BookAccount.money(account.id),
    currency: account.currency,
    at: at,
  );

  /// Fuliza owed on [account] just before [at]; nothing for accounts that
  /// cannot owe Fuliza.
  int fulizaOwedAt(AccountOpening account, {required DateTime at}) =>
      account.canOweFuliza
      ? balanceOf(
          BookAccount.fulizaOwed(account.id),
          currency: account.currency,
          at: at,
        )
      : 0;

  /// What [account] is really worth just before [at]: its money less any
  /// Fuliza owed. The figure Balances and On hand show.
  int heldAt(AccountOpening account, {required DateTime at}) =>
      walletAt(account, at: at) - fulizaOwedAt(account, at: at);

  /// The money in the [accounts] that pass [where] just before [at].
  int totalWalletAt(
    Iterable<AccountOpening> accounts, {
    required DateTime at,
    required bool Function(AccountOpening account) where,
  }) => accounts.where(where).fold(0, (sum, a) => sum + walletAt(a, at: at));

  /// What the [accounts] that pass [where] are really worth just before
  /// [at], Fuliza owed taken off.
  int totalHeldAt(
    Iterable<AccountOpening> accounts, {
    required DateTime at,
    required bool Function(AccountOpening account) where,
  }) => accounts.where(where).fold(0, (sum, a) => sum + heldAt(a, at: at));
}
