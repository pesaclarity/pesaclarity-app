import '../enums.dart';
import '../ledger/activity_feed.dart';
import '../ledger/activity_lines.dart';
import '../ledger/balances.dart';
import '../ledger/ledger_entry.dart';
import '../time/calendar.dart';

/// Where a business keeps its money: the cash book's columns.
enum CashColumn {
  cash('Cash'),
  mpesa('M-Pesa'),
  bank('Bank');

  const CashColumn(this.label);

  final String label;
}

/// The column an account of [type] sits in; null for savings, which stay
/// out of the cash book.
CashColumn? cashColumnOf(AccountType type) => switch (type) {
  AccountType.cash => CashColumn.cash,
  AccountType.mpesa => CashColumn.mpesa,
  AccountType.bank || AccountType.other => CashColumn.bank,
  AccountType.sacco || AccountType.moneyMarket => null,
};

/// One day of the cash book.
class CashBookDay {
  const CashBookDay({
    required this.date,
    required this.lines,
    required this.inMinor,
    required this.outMinor,
  });

  final CalendarDate date;

  /// Newest first.
  final List<ActivityLine> lines;

  /// Money that came into the book.
  final int inMinor;

  /// Money that left the book, transaction costs included.
  final int outMinor;
}

/// The cash book: what each column holds now, and day by day what came in
/// and went out.
class CashBook {
  const CashBook({required this.balances, required this.days});

  /// Built from every entry in [history] before [to], with [days] from
  /// [from] on.
  ///
  /// A move between two of the book's own accounts shows once and counts
  /// neither in nor out, so in less out is how much the book changed. Money
  /// moved to or from savings counts, since it left or joined the book.
  factory CashBook.of(
    Iterable<LedgerEntry> history, {
    required Iterable<AccountOpening> accounts,
    required DateTime to,
    required CalendarDate from,
    String? currency,
  }) {
    final all = history.toList();
    final money = [
      for (final a in accounts)
        if (cashColumnOf(a.type) != null &&
            (currency == null || a.currency == currency))
          a,
    ];
    final balances = <CashColumn, int>{
      for (final column in CashColumn.values)
        if (money.any((a) => cashColumnOf(a.type) == column))
          column: totalBalanceAt(
            money,
            all,
            at: to,
            where: (a) => cashColumnOf(a.type) == column,
          ),
    };

    final ids = {for (final a in money) a.id};
    final accountOf = {for (final e in all) e.id: e.accountId};
    bool withinBook(LedgerEntry e) =>
        e.transferPairId != null && ids.contains(accountOf[e.transferPairId]);

    final shown = [
      for (final e in all)
        if (ids.contains(e.accountId) &&
            (currency == null || e.currency == currency) &&
            !e.occurredAt.isBefore(from.startInstant) &&
            e.occurredAt.isBefore(to))
          e,
    ];
    final inOf = <CalendarDate, int>{};
    final outOf = <CalendarDate, int>{};
    for (final e in shown) {
      outOf[e.date] = (outOf[e.date] ?? 0) + e.feeMinor;
      if (withinBook(e)) continue;
      final totals = e.isInflow ? inOf : outOf;
      totals[e.date] = (totals[e.date] ?? 0) + e.amountMinor;
    }
    final days = [
      for (final day in buildActivityFeed(shown, all: all))
        CashBookDay(
          date: day.date,
          lines: day.lines,
          inMinor: inOf[day.date] ?? 0,
          outMinor: outOf[day.date] ?? 0,
        ),
    ];
    return CashBook(balances: balances, days: days);
  }

  /// Each column's balance, in column order, for the columns the business
  /// has an account in.
  final Map<CashColumn, int> balances;

  /// Newest first.
  final List<CashBookDay> days;
}
