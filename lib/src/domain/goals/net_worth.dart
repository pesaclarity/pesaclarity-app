import '../ledger/balances.dart';
import '../ledger/ledger_entry.dart';
import '../time/calendar.dart';

/// What the user owns less what they owe, now and at the start of the month.
class NetWorth {
  const NetWorth({
    required this.assetsMinor,
    required this.debtsMinor,
    required this.startOfMonthMinor,
  });

  /// Net worth at [now] in [currency]: every account balance plus money lent
  /// and still owed back, less every debt.
  ///
  /// The start of the month uses balances just before the month began, the
  /// lent money then outstanding, and today's debts plus what was repaid on
  /// them since.
  factory NetWorth.at({
    required DateTime now,
    required Iterable<AccountOpening> accounts,
    required Iterable<LedgerEntry> entries,
    required int debtsOwedMinor,
    required int debtsRepaidThisMonthMinor,
    required int lentOutstandingMinor,
    required int lentOutstandingAtMonthStartMinor,
    String currency = 'KES',
  }) {
    final monthStart = YearMonth.nairobi(now).startInstant;
    bool inCurrency(AccountOpening a) => a.currency == currency;
    final list = entries.toList();
    final balancesNow = totalBalanceAt(
      accounts,
      list,
      at: now,
      where: inCurrency,
    );
    final balancesThen = totalBalanceAt(
      accounts,
      list,
      at: monthStart,
      where: inCurrency,
    );
    return NetWorth(
      assetsMinor: balancesNow + lentOutstandingMinor,
      debtsMinor: debtsOwedMinor,
      startOfMonthMinor:
          balancesThen +
          lentOutstandingAtMonthStartMinor -
          (debtsOwedMinor + debtsRepaidThisMonthMinor),
    );
  }

  final int assetsMinor;
  final int debtsMinor;
  final int startOfMonthMinor;

  int get valueMinor => assetsMinor - debtsMinor;

  /// Change since the month began; positive is better.
  int get changeThisMonthMinor => valueMinor - startOfMonthMinor;
}
