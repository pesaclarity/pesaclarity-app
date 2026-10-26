import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/plan/surplus_split.dart';

void main() {
  test('splits the surplus between debt and savings', () {
    final split = SurplusSplit.of(
      expectedIncomeMinor: 10000000,
      plannedOutgoingMinor: 8000000,
    );
    expect(split.surplusMinor, 2000000);
    expect(split.toDebtMinor, 1000000);
    expect(split.toSavingsMinor, 1000000);
    expect(split.shortfallMinor, 0);
  });

  test('rounds the debt share down and gives savings the rest', () {
    final split = SurplusSplit.of(
      expectedIncomeMinor: 1001,
      plannedOutgoingMinor: 0,
      debtShareBasisPoints: 3333,
    );
    expect(split.toDebtMinor, 333);
    expect(split.toSavingsMinor, 668);
    expect(split.toDebtMinor + split.toSavingsMinor, split.surplusMinor);
  });

  test('sends everything to savings with no debt', () {
    final split = SurplusSplit.of(
      expectedIncomeMinor: 500,
      plannedOutgoingMinor: 100,
      hasDebt: false,
    );
    expect(split.toDebtMinor, 0);
    expect(split.toSavingsMinor, 400);
  });

  test('can send everything to debt', () {
    final split = SurplusSplit.of(
      expectedIncomeMinor: 500,
      plannedOutgoingMinor: 100,
      debtShareBasisPoints: 10000,
    );
    expect(split.toDebtMinor, 400);
    expect(split.toSavingsMinor, 0);
  });

  test('splits nothing when the plan uses all income or more', () {
    final even = SurplusSplit.of(
      expectedIncomeMinor: 500,
      plannedOutgoingMinor: 500,
    );
    expect(even.toDebtMinor + even.toSavingsMinor, 0);
    expect(even.shortfallMinor, 0);

    final short = SurplusSplit.of(
      expectedIncomeMinor: 500,
      plannedOutgoingMinor: 800,
    );
    expect(short.surplusMinor, -300);
    expect(short.shortfallMinor, 300);
    expect(short.toDebtMinor + short.toSavingsMinor, 0);
  });

  test('rejects a share outside 0 to 100 percent', () {
    expect(
      () => SurplusSplit.of(
        expectedIncomeMinor: 1,
        plannedOutgoingMinor: 0,
        debtShareBasisPoints: 10001,
      ),
      throwsArgumentError,
    );
  });
}
