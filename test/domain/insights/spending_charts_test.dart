import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/insights/spending_charts.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  final today = CalendarDate(2026, 10, 27); // a Tuesday

  group('windows', () {
    test('a week starts on Monday', () {
      final w = ChartWindow.of(ChartPeriod.week, today);
      expect(w.start, CalendarDate(2026, 10, 26));
      expect(w.days, 7);
      expect(w.previous(ChartPeriod.week).start, CalendarDate(2026, 10, 19));
    });

    test('months and years follow the calendar', () {
      final m = ChartWindow.of(ChartPeriod.month, today);
      expect((m.start, m.days), (CalendarDate(2026, 10, 1), 31));
      expect(m.previous(ChartPeriod.month).days, 30);
      final y = ChartWindow.of(ChartPeriod.year, today);
      expect((y.start, y.days), (CalendarDate(2026, 1, 1), 365));
      expect(y.previous(ChartPeriod.year).start, CalendarDate(2025, 1, 1));
    });
  });

  test('splits spending by category with fees on their own', () {
    final chart = SpendingChart.of(
      [
        entry(
          at: eat(2026, 10, 2),
          amount: kes(500),
          categoryId: 1,
          fee: kes(7),
        ),
        entry(at: eat(2026, 10, 3), amount: kes(1500), categoryId: 2),
        entry(at: eat(2026, 10, 4), amount: kes(200)),
        // Income and other months stay out.
        inflow(at: eat(2026, 10, 5), amount: kes(9000)),
        entry(at: eat(2026, 11, 1), amount: kes(999), categoryId: 1),
      ],
      period: ChartPeriod.month,
      today: today,
    );
    expect(chart.slices, [
      (key: const CategorySlice(2), amountMinor: kes(1500)),
      (key: const CategorySlice(1), amountMinor: kes(500)),
      (key: const UncategorisedSlice(), amountMinor: kes(200)),
      (key: const FeesSlice(), amountMinor: kes(7)),
    ]);
    expect(chart.totalMinor, kes(2207));
  });

  test('own transfers are not spending, and refunds come off', () {
    final chart = SpendingChart.of(
      [
        entry(at: eat(2026, 10, 2), amount: kes(800), categoryId: 1),
        entry(at: eat(2026, 10, 2), amount: kes(5000), transferPairId: 9),
        inflow(
          at: eat(2026, 10, 3),
          amount: kes(300),
          kind: TransactionKind.reversal,
          categoryId: 1,
        ),
      ],
      period: ChartPeriod.month,
      today: today,
    );
    expect(chart.slices, [
      (key: const CategorySlice(1), amountMinor: kes(500)),
    ]);
  });

  test('puts the smaller slices together', () {
    final chart = SpendingChart.of(
      [
        for (var c = 1; c <= 8; c++)
          entry(at: eat(2026, 10, 2), amount: kes(100 * c), categoryId: c),
      ],
      period: ChartPeriod.month,
      today: today,
      maxSlices: 4,
    );
    expect(chart.slices.map((s) => s.key), [
      const CategorySlice(8),
      const CategorySlice(7),
      const CategorySlice(6),
      const OtherSlice(),
    ]);
    expect(chart.slices.last.amountMinor, kes(100 + 200 + 300 + 400 + 500));
  });

  test('runs totals to today, against the whole window before', () {
    final chart = SpendingChart.of(
      [
        entry(at: eat(2026, 10, 1), amount: kes(100)),
        entry(at: eat(2026, 10, 3), amount: kes(50)),
        entry(at: eat(2026, 9, 1), amount: kes(400)),
        entry(at: eat(2026, 9, 30), amount: kes(10)),
      ],
      period: ChartPeriod.month,
      today: CalendarDate(2026, 10, 3),
    );
    expect(chart.cumulative, [kes(100), kes(100), kes(150)]);
    expect(chart.previousCumulative, hasLength(30));
    expect(chart.previousCumulative.last, kes(410));
    // 150 so far against 400 by the 3rd of September.
    expect(chart.changeToDateMinor, kes(-250));
  });

  test('has no data in an empty ledger', () {
    final chart = SpendingChart.of(
      const [],
      period: ChartPeriod.week,
      today: today,
    );
    expect(chart.hasData, isFalse);
    expect(chart.changeToDateMinor, 0);
  });
}
