import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/debts/fuliza_tracker.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

void main() {
  final entries = [
    // Drawn late on 30 October, repaid on 2 November.
    entry(
      at: eat(2026, 10, 30, 23),
      amount: kes(500),
      kind: TransactionKind.fulizaDraw,
    ),
    entry(
      at: eat(2026, 11, 2, 9),
      amount: kes(510),
      kind: TransactionKind.fulizaRepayment,
    ),
    // Drawn and repaid the same day.
    entry(
      at: eat(2026, 11, 10, 8),
      amount: kes(100),
      kind: TransactionKind.fulizaDraw,
    ),
    entry(
      at: eat(2026, 11, 10, 18),
      amount: kes(101),
      kind: TransactionKind.fulizaRepayment,
    ),
    // Two draws, cleared on 8 December.
    entry(
      at: eat(2026, 12, 1, 7),
      amount: kes(200),
      kind: TransactionKind.fulizaDraw,
    ),
    entry(
      at: eat(2026, 12, 5, 7),
      amount: kes(300),
      kind: TransactionKind.fulizaDraw,
    ),
    entry(
      at: eat(2026, 12, 8, 7),
      amount: kes(506),
      kind: TransactionKind.fulizaRepayment,
    ),
    // Still owed at the end.
    entry(
      at: eat(2026, 12, 20, 7),
      amount: kes(50),
      kind: TransactionKind.fulizaDraw,
    ),
    // Not Fuliza.
    entry(at: eat(2026, 12, 21, 7), amount: kes(999)),
  ];

  test('counts days overdrawn across month boundaries', () {
    final tracker = FulizaTracker.of(entries, asOf: CalendarDate(2026, 12, 31));
    expect(tracker.daysOverdrawnIn(YearMonth(2026, 10)), 2);
    expect(tracker.daysOverdrawnIn(YearMonth(2026, 11)), 3);
    expect(tracker.daysOverdrawnIn(YearMonth(2026, 12)), 8 + 12);
    expect(tracker.outstandingMinor, kes(50));
  });

  test('without asOf, owing stops at the last entry', () {
    final tracker = FulizaTracker.of(entries);
    expect(tracker.daysOverdrawnIn(YearMonth(2026, 12)), 8 + 1);
  });

  test('reports draws and fees from the Fuliza ledger', () {
    final months = FulizaTracker.of(
      entries,
      asOf: CalendarDate(2026, 12, 31),
    ).months(YearMonth(2026, 10), YearMonth(2026, 12));

    expect(months.map((m) => m.month), [
      YearMonth(2026, 10),
      YearMonth(2026, 11),
      YearMonth(2026, 12),
    ]);
    expect(months.map((m) => m.usage.drawsMinor), [
      kes(500),
      kes(100),
      kes(550),
    ]);
    expect(months.map((m) => m.usage.drawCount), [1, 1, 3]);
    expect(months.map((m) => m.usage.feesMinor), [0, kes(11), kes(6)]);
    expect(months.map((m) => m.daysOverdrawn), [2, 3, 20]);
  });

  test('flags climbing use: more days overdrawn and more drawn', () {
    final tracker = FulizaTracker.of(entries, asOf: CalendarDate(2026, 12, 31));
    expect(tracker.month(YearMonth(2026, 10)).isClimbing, isTrue);
    expect(
      tracker.month(YearMonth(2026, 11)).isClimbing,
      isFalse,
      reason: 'more days, but less drawn',
    );
    expect(tracker.month(YearMonth(2026, 12)).isClimbing, isTrue);
    expect(tracker.month(YearMonth(2027, 1)).isClimbing, isFalse);
  });

  test('no Fuliza means nothing to track', () {
    final tracker = FulizaTracker.of([
      entry(at: eat(2026, 11, 1), amount: 100),
    ]);
    final month = tracker.month(YearMonth(2026, 11));
    expect(month.daysOverdrawn, 0);
    expect(month.usage.drawsMinor, 0);
    expect(month.isClimbing, isFalse);
  });
}
