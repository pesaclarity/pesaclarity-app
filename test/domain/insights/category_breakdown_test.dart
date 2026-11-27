import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/insights/category_breakdown.dart';
import 'package:pesaclarity/src/domain/insights/spending_charts.dart';
import 'package:pesaclarity/src/domain/ledger/ledger_entry.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

var _id = 1;

const _transport = 2;
const _fuel = 10;
const _uber = 11;

LedgerEntry _out(DateTime at, int shillings, {int? sub, int category = 2}) =>
    LedgerEntry(
      id: _id++,
      accountId: 1,
      occurredAt: at,
      amountMinor: kes(shillings),
      direction: TransactionDirection.outflow,
      kind: TransactionKind.till,
      categoryId: category,
      subcategoryId: sub,
      categoryType: CategoryType.expense,
    );

void main() {
  final today = CalendarDate(2026, 11, 20);
  final window = ChartWindow.of(ChartPeriod.month, today);
  final entries = [
    _out(eat(2026, 11, 2), 6000, sub: _fuel),
    _out(eat(2026, 11, 9), 3800, sub: _fuel),
    _out(eat(2026, 11, 3), 450, sub: _uber),
    _out(eat(2026, 11, 4), 1310),
    // Another category, and last month.
    _out(eat(2026, 11, 5), 999, category: 1),
    _out(eat(2026, 10, 5), 12000, sub: _fuel),
  ];

  test('splits a category by subcategory, its own spending last', () {
    final b = CategoryBreakdown.of(
      entries,
      categoryId: _transport,
      window: window,
      previous: window.previous(ChartPeriod.month),
    );
    expect(b.rows.map((r) => (r.subcategoryId, r.amountMinor, r.count)), [
      (_fuel, kes(9800), 2),
      (_uber, kes(450), 1),
      (null, kes(1310), 1),
    ]);
    expect(b.totalMinor, kes(11560));
    expect(b.count, 4);
    expect(b.previousMinor, kes(12000));
    expect(b.changeMinor, kes(-440));
    expect(b.percentOf(b.rows.first), 85);
  });

  test('the ring keeps the category as one slice with the same total', () {
    final chart = SpendingChart.of(
      entries,
      period: ChartPeriod.month,
      today: today,
    );
    final slice = chart.slices.firstWhere(
      (s) => s.key == const CategorySlice(_transport),
    );
    expect(slice.amountMinor, kes(11560));
    expect(
      chart.slices.any((s) => s.key == const CategorySlice(_fuel)),
      isFalse,
    );
  });
}
