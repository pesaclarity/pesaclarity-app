import '../books/journal_balances.dart';
import '../time/calendar.dart';
import 'balances.dart';
import 'ledger_entry.dart';

/// Day-to-day money at the start of a day: each day-to-day account's real
/// worth (Fuliza owed taken off), less the rainy day fund. Savings accounts
/// (SACCO, money market) are not counted.
class OnHand {
  const OnHand({
    required this.byAccount,
    required this.rainyDayMinor,
    required this.fulizaOwedMinor,
  });

  /// What day-to-day [accounts] held at the start of [today], from the
  /// journal's [balances]. A balance set by hand today (in [entries])
  /// counts from the start of the day, so Home follows the figure the
  /// person just typed.
  factory OnHand.at(
    Iterable<AccountOpening> accounts,
    Iterable<LedgerEntry> entries, {
    required JournalBalances balances,
    required CalendarDate today,
    required int rainyDayMinor,
  }) {
    final list = entries.toList();
    final start = today.startInstant;
    final byAccount = <int, int>{};
    var owed = 0;
    for (final account in accounts) {
      if (account.isSavings) continue;
      final setToday = list
          .where(
            (e) =>
                e.accountId == account.id &&
                e.currency == account.currency &&
                e.isCorrection &&
                e.date == today,
          )
          .fold(0, (sum, e) => sum + e.signedMinor);
      byAccount[account.id] = balances.heldAt(account, at: start) + setToday;
      owed += balances.fulizaOwedAt(account, at: today.addDays(1).startInstant);
    }
    return OnHand(
      byAccount: byAccount,
      rainyDayMinor: rainyDayMinor,
      fulizaOwedMinor: owed,
    );
  }

  /// Each day-to-day account's worth, by account id.
  final Map<int, int> byAccount;

  /// Money in the rainy day fund: still in the accounts, not for spending.
  final int rainyDayMinor;

  /// Fuliza owed now, already taken off its account in [byAccount].
  final int fulizaOwedMinor;

  int get accountsMinor => byAccount.values.fold(0, (sum, v) => sum + v);

  /// On hand: the accounts less the rainy day fund. Below zero when Fuliza
  /// or an overdraft is more than the money.
  int get totalMinor => accountsMinor - rainyDayMinor;
}
