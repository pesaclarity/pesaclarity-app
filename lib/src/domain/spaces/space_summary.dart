import '../enums.dart';
import '../ledger/ledger_entry.dart';
import '../ledger/ledger_role.dart';
import '../ledger/ledger_totals.dart';
import '../time/calendar.dart';
import 'space.dart';
import 'space_categories.dart';

/// Months a farm's season covers, this one included.
const farmSeasonMonths = 6;

/// Category rows a profit summary lists.
const summaryRows = 4;

/// One category's money in a summary.
class SummaryRow {
  const SummaryRow({
    required this.name,
    required this.amountMinor,
    required this.isIncome,
  });

  final String name;
  final int amountMinor;
  final bool isIncome;
}

/// A category as the summary needs it.
typedef SummaryCategory = ({String? key, String name, CategoryType type});

/// What the top of Home shows first for a space that is not Personal.
class SpaceSummary {
  const SpaceSummary({
    required this.kind,
    required this.from,
    required this.inMinor,
    required this.outMinor,
    required this.balanceMinor,
    this.rows = const [],
    this.paidYourselfMinor = 0,
    this.payersCount = 0,
    this.loansOutCount = 0,
  });

  /// Sums [history] from the start of the period to [today].
  ///
  /// Money in is income; money out is spending, fees and tax, so own
  /// transfers, savings, borrowing and paying yourself are left out.
  factory SpaceSummary.of(
    SpaceKind kind,
    Iterable<LedgerEntry> history, {
    required CalendarDate today,
    required Map<int, SummaryCategory> categories,
    required int balanceMinor,
  }) {
    final month = today.yearMonth.firstDay;
    final from = kind == SpaceKind.farm
        ? CalendarDate(month.year, month.month - (farmSeasonMonths - 1), 1)
        : month;
    final start = from.startInstant;
    final end = today.addDays(1).startInstant;
    final totals = LedgerTotals.of(history, from: start, to: end);

    final byCategory = <String, (int, bool)>{};
    var paidYourself = 0;
    final payers = <int>{};
    var loansOut = 0;
    for (final e in history) {
      if (e.occurredAt.isBefore(start) || !e.occurredAt.isBefore(end)) {
        continue;
      }
      final category = e.categoryId == null ? null : categories[e.categoryId];
      final role = roleOf(e);
      if (category?.key == ownerPayKey && e.isOutflow) {
        paidYourself += e.amountMinor;
      }
      if (role == LedgerRole.income && e.payeeId != null) {
        if (kind != SpaceKind.savingsGroup ||
            category?.key == 'contributions') {
          payers.add(e.payeeId!);
        }
      }
      if (category?.key == 'member_loans' && e.isOutflow) loansOut++;
      final counts =
          role == LedgerRole.income ||
          role == LedgerRole.spending ||
          role == LedgerRole.tax;
      if (category != null && counts) {
        final (sum, income) = byCategory[category.name] ?? (0, e.isInflow);
        byCategory[category.name] = (sum + e.amountMinor, income);
      }
    }
    final rows =
        [
          for (final MapEntry(:key, :value) in byCategory.entries)
            SummaryRow(name: key, amountMinor: value.$1, isIncome: value.$2),
        ]..sort((a, b) {
          if (a.isIncome != b.isIncome) return a.isIncome ? -1 : 1;
          return b.amountMinor.compareTo(a.amountMinor);
        });

    return SpaceSummary(
      kind: kind,
      from: from,
      inMinor: totals.incomeMinor,
      outMinor: totals.spendingMinor + totals.feesMinor + totals.taxMinor,
      balanceMinor: balanceMinor,
      rows: rows.take(summaryRows).toList(),
      paidYourselfMinor: paidYourself,
      payersCount: payers.length,
      loansOutCount: loansOut,
    );
  }

  final SpaceKind kind;

  /// The first day counted: this month, or the season for a farm.
  final CalendarDate from;
  final int inMinor;
  final int outMinor;

  /// Money across the space's accounts now.
  final int balanceMinor;

  /// The largest categories, money in first.
  final List<SummaryRow> rows;
  final int paidYourselfMinor;

  /// People who paid money in: members for a savings group.
  final int payersCount;
  final int loansOutCount;

  int get profitMinor => inMinor - outMinor;

  /// The label over the main figure.
  String get headline => switch (kind) {
    SpaceKind.business || SpaceKind.rentalProperty => 'Profit this month',
    SpaceKind.farm => 'Profit this season',
    SpaceKind.household => 'Left for the home this month',
    SpaceKind.savingsGroup => "In the group's pot",
    SpaceKind.personal || SpaceKind.other => 'Balance',
  };

  /// The main figure.
  int get figureMinor => switch (kind) {
    SpaceKind.business ||
    SpaceKind.rentalProperty ||
    SpaceKind.farm ||
    SpaceKind.household => profitMinor,
    SpaceKind.savingsGroup ||
    SpaceKind.personal ||
    SpaceKind.other => balanceMinor,
  };
}
