import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/income/income_pattern.dart';
import 'package:pesaclarity/src/domain/income/income_sources.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

import '../fixtures.dart';

/// Friday 14 November 2026.
final today = CalendarDate(2026, 11, 14);

void main() {
  test('support every two weeks is a steady rhythm', () {
    final history = [
      for (final day in [4, 18])
        inflow(
          at: eat(2026, 10, day),
          amount: kes(5000),
          payeeId: 1,
          categoryType: CategoryType.income,
        ),
      inflow(
        at: eat(2026, 11, 1),
        amount: kes(5000),
        payeeId: 1,
        categoryType: CategoryType.income,
      ),
    ];
    final pattern = IncomePattern.of(history, today: today);
    expect(pattern.arrivalDays, 3);
    expect(pattern.senders, 1);
    expect(pattern.typicalGapDays, 14);
    expect(pattern.steady, isTrue);
    expect(pattern.nextExpected(today), CalendarDate(2026, 11, 15));
  });

  test('money most days is not a rhythm to plan around', () {
    final history = [
      for (var d = 1; d <= 13; d++)
        inflow(
          at: eat(2026, 11, d),
          amount: kes(300 + d * 20),
          payeeId: d,
          categoryType: CategoryType.income,
        ),
    ];
    final pattern = IncomePattern.of(history, today: today);
    expect(pattern.steady, isFalse);
    expect(pattern.nextExpected(today), isNull);
    expect(pattern.senders, 13);
  });

  test('borrowing is never income', () {
    final history = [
      inflow(
        at: eat(2026, 11, 3),
        amount: kes(2000),
        kind: TransactionKind.fulizaDraw,
      ),
    ];
    expect(IncomePattern.of(history, today: today).arrivalDays, 0);
  });

  test('sources say which plan fits', () {
    expect(const IncomeSources({IncomeSource.salary}).salaryOnly, isTrue);
    expect(
      const IncomeSources({IncomeSource.salary, IncomeSource.gigs}).irregular,
      isTrue,
    );
    expect(const IncomeSources({IncomeSource.seasonal}).noDate, isTrue);
    expect(const IncomeSources({IncomeSource.support}).noDate, isFalse);
    final back = IncomeSources.fromJson(
      const IncomeSources({IncomeSource.support, IncomeSource.gigs}).toJson(),
    );
    expect(back.picked, {IncomeSource.support, IncomeSource.gigs});
  });
}
