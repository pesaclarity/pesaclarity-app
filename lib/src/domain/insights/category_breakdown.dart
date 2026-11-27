import '../../core/money/money.dart';
import '../books/journal_balances.dart';
import '../ledger/fuliza.dart';
import '../ledger/ledger_entry.dart';
import 'spending_charts.dart';

/// One line of a category's breakdown: a subcategory, or the parent's own
/// spending when [subcategoryId] is null.
typedef BreakdownRow = ({int? subcategoryId, int amountMinor, int count});

/// A top-level category's spending in a window, split by subcategory, as
/// Insights opens it from its slice of the ring. The parent's total is the
/// slice's, so the two always agree.
class CategoryBreakdown {
  const CategoryBreakdown({
    required this.categoryId,
    required this.window,
    required this.rows,
    required this.previousMinor,
  });

  /// [categoryId]'s spending in [window] of [period] from [history], which
  /// should reach back to the previous window and a month before it, as
  /// [SpendingChart.of] wants.
  factory CategoryBreakdown.of(
    Iterable<LedgerEntry> history, {
    required int categoryId,
    required ChartWindow window,
    required ChartWindow previous,
    String? currency,
    JournalBalances? journal,
  }) {
    currency ??= BaseCurrency.code;
    final all = history.where((e) => e.currency == currency).toList();
    final fuliza = FulizaLedger.of(all);
    final slice = CategorySlice(categoryId);
    final amounts = <int?, int>{};
    final counts = <int?, int>{};
    var previousMinor = 0;
    for (final entry in all) {
      if (entry.categoryId != categoryId) continue;
      final inWindow = window.contains(entry.date);
      if (!inWindow && !previous.contains(entry.date)) continue;
      var amount = 0;
      for (final (key, minor) in spendingPartsOf(
        entry,
        fuliza,
        journal: journal,
      )) {
        if (key == slice) amount += minor;
      }
      if (amount == 0) continue;
      if (!inWindow) {
        previousMinor += amount;
        continue;
      }
      final sub = entry.subcategoryId;
      amounts[sub] = (amounts[sub] ?? 0) + amount;
      counts[sub] = (counts[sub] ?? 0) + 1;
    }
    // Subcategories largest first, then the parent's own spending.
    final rows = <BreakdownRow>[
      for (final MapEntry(:key, :value) in amounts.entries)
        if (key != null)
          (subcategoryId: key, amountMinor: value, count: counts[key]!),
    ]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    if (amounts[null] case final own? when own != 0) {
      rows.add((subcategoryId: null, amountMinor: own, count: counts[null]!));
    }
    return CategoryBreakdown(
      categoryId: categoryId,
      window: window,
      rows: rows,
      previousMinor: previousMinor,
    );
  }

  final int categoryId;
  final ChartWindow window;
  final List<BreakdownRow> rows;

  /// Spent on the category in the window before.
  final int previousMinor;

  int get totalMinor => rows.fold(0, (sum, r) => sum + r.amountMinor);

  int get count => rows.fold(0, (sum, r) => sum + r.count);

  /// This window less the one before; negative when spending is lower.
  int get changeMinor => totalMinor - previousMinor;

  /// [row]'s whole-number share of the total.
  int percentOf(BreakdownRow row) =>
      totalMinor <= 0 ? 0 : (row.amountMinor * 100 / totalMinor).round();
}
