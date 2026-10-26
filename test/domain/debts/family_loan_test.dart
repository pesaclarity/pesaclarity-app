import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/debts/debt.dart';
import 'package:pesaclarity/src/domain/debts/family_loan.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  final agreed = [
    DebtInstalment(dueDate: CalendarDate(2027, 3, 10), amountMinor: 10000),
    DebtInstalment(dueDate: CalendarDate(2027, 1, 10), amountMinor: 10000),
    DebtInstalment(dueDate: CalendarDate(2027, 2, 10), amountMinor: 10000),
  ];

  test('part payments clear the oldest instalment first', () {
    final status = FamilyLoanStatus.of(
      amountMinor: 30000,
      agreed: agreed,
      payments: [
        LoanPayment(date: CalendarDate(2027, 1, 5), amountMinor: 4000),
        LoanPayment(date: CalendarDate(2027, 2, 1), amountMinor: 8000),
      ],
      today: CalendarDate(2027, 2, 15),
    );
    expect(status.paidMinor, 12000);
    expect(status.remainingMinor, 18000);
    expect(status.overdueMinor, 8000);
    expect(status.remainingInstalments, [
      DebtInstalment(dueDate: CalendarDate(2027, 2, 10), amountMinor: 8000),
      DebtInstalment(dueDate: CalendarDate(2027, 3, 10), amountMinor: 10000),
    ]);
    expect(status.nextDue!.amountMinor, 8000);
    expect(status.unscheduledMinor, 0);
    expect(status.isCleared, isFalse);
  });

  test('an instalment due today is not yet overdue', () {
    final status = FamilyLoanStatus.of(
      amountMinor: 30000,
      agreed: agreed,
      payments: const [],
      today: CalendarDate(2027, 1, 10),
    );
    expect(status.overdueMinor, 0);
    expect(status.nextDue!.dueDate, CalendarDate(2027, 1, 10));
  });

  test('a plan short of the loan leaves an unscheduled remainder', () {
    final status = FamilyLoanStatus.of(
      amountMinor: 50000,
      agreed: agreed,
      payments: const [],
      today: CalendarDate(2027, 1, 1),
    );
    expect(status.unscheduledMinor, 20000);
  });

  test('paying it all clears the loan', () {
    final status = FamilyLoanStatus.of(
      amountMinor: 30000,
      agreed: agreed,
      payments: [
        LoanPayment(date: CalendarDate(2026, 12, 24), amountMinor: 30000),
      ],
      today: CalendarDate(2027, 6, 1),
    );
    expect(status.isCleared, isTrue);
    expect(status.overdueMinor, 0);
    expect(status.nextDue, isNull);
  });
}
