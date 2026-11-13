import '../ledger/ledger_entry.dart';
import '../time/calendar.dart';
import 'matcher.dart';
import 'periods.dart';

/// One named amount from the records: a bill, a debt, a goal, an item sold.
class AskLine {
  const AskLine(
    this.name,
    this.amountMinor, {
    this.count,
    this.date,
    this.extraMinor,
  });

  final String name;
  final int amountMinor;

  /// How many there were, such as sales of an item.
  final int? count;

  /// When it is due or happened.
  final CalendarDate? date;

  /// A second amount, such as a goal's target.
  final int? extraMinor;
}

/// Safe to spend as Home works it out.
class AskSafeToSpend {
  const AskSafeToSpend({required this.leftTodayMinor, required this.overMinor});

  final int leftTodayMinor;
  final int overMinor;
}

/// Everything Ask reads, from the open space only. The app's version reads
/// the space's repositories and the same providers its screens use, so an
/// answer always matches what the screen shows.
abstract interface class AskDataSource {
  /// Categories, payees, accounts and stock items Ask can name.
  Future<List<AskEntity>> entities();

  /// Words the person taught Ask in this space.
  Future<List<AskShortcut>> shortcuts();

  /// Ledger entries with time in `[from, to)`, oldest first.
  Future<List<LedgerEntry>> entries(DateTime from, DateTime to);

  /// Null until there is a day-to-day budget.
  Future<AskSafeToSpend?> safeToSpend();

  Future<List<AskLine>> billsDue();

  /// Each with its monthly cost.
  Future<List<AskLine>> subscriptions();

  /// Each with what is left to pay.
  Future<List<AskLine>> debts();

  /// Money lent, each with what is still to come back.
  Future<List<AskLine>> lent();

  /// Customers and people who owe this space.
  Future<List<AskLine>> owedToMe();

  /// Each with what is saved and, as [AskLine.extraMinor], the target.
  Future<List<AskLine>> goals();

  /// Each account and its balance now.
  Future<List<AskLine>> balances();

  /// Sales in [period]: the total and how many, as one line.
  Future<AskLine> sales(AskPeriod period);

  /// Each item sold in [period], with what it brought in and how many sales.
  Future<List<AskLine>> itemsSold(AskPeriod period);

  /// Profit in [period], or null when the space keeps no books.
  Future<int?> profit(AskPeriod period);

  /// Items running low, with what is left as [AskLine.count] in thousandths.
  Future<List<AskLine>> lowStock();
}
