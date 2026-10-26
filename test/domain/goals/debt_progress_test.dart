import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/debts/debt.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/goals/debt_progress.dart';

void main() {
  Debt debt(int id, int balance) => Debt(
    id: id,
    lender: 'Test $id',
    type: DebtType.bankLoan,
    balanceMinor: balance,
  );

  test('sums paid, remaining and cleared across debts', () {
    final progress = DebtProgress.of(
      [debt(1, 6000), debt(2, 0), debt(3, 4000)],
      {1: 10000, 2: 5000, 3: 5000},
    );
    expect(progress.count, 3);
    expect(progress.clearedCount, 1);
    expect(progress.remainingMinor, 10000);
    expect(progress.originalMinor, 20000);
    expect(progress.paidFraction, closeTo(0.5, 1e-9));
    expect(progress.open.map((l) => l.debt.id), [1, 3]);
    expect(progress.lines.first.paidFraction, closeTo(0.4, 1e-9));
  });

  test('a balance above the start counts as nothing paid', () {
    final progress = DebtProgress.of([debt(1, 12000)], {1: 10000});
    expect(progress.lines.single.originalMinor, 12000);
    expect(progress.paidFraction, 0);
  });

  test('no debts reads as all paid', () {
    final progress = DebtProgress.of(const [], const {});
    expect(progress.paidFraction, 1);
    expect(progress.remainingMinor, 0);
  });
}
