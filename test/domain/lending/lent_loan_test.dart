import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/debts/family_loan.dart';
import 'package:pesaclarity/src/domain/lending/lent_loan.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

void main() {
  final today = CalendarDate(2026, 11, 5);

  LentLoan loan({
    CalendarDate? due,
    List<LoanPayment> payments = const [],
    String person = 'John Kamau',
  }) => LentLoan(
    id: 1,
    person: person,
    amountMinor: 500000,
    lentOn: CalendarDate(2026, 10, 3),
    dueDate: due,
    payments: payments,
  );

  final part = [
    LoanPayment(date: CalendarDate(2026, 10, 20), amountMinor: 200000),
  ];

  test('status treats the due date as one instalment', () {
    final status = loan(
      due: CalendarDate(2026, 10, 31),
      payments: part,
    ).status(today);
    expect(status.paidMinor, 200000);
    expect(status.remainingMinor, 300000);
    expect(status.overdueMinor, 300000);
    expect(status.nextDue!.dueDate, CalendarDate(2026, 10, 31));
  });

  test('with no due date nothing is overdue', () {
    final status = loan(payments: part).status(today);
    expect(status.overdueMinor, 0);
    expect(status.nextDue, isNull);
    expect(status.remainingMinor, 300000);
  });

  test('outstanding at a date counts only earlier payments', () {
    final l = loan(payments: part);
    expect(l.outstandingAt(CalendarDate(2026, 10, 1)), 0);
    expect(l.outstandingAt(CalendarDate(2026, 10, 3)), 0);
    expect(l.outstandingAt(CalendarDate(2026, 10, 4)), 500000);
    expect(l.outstandingAt(CalendarDate(2026, 11, 1)), 300000);
  });

  test('the reminder is polite and uses the first name', () {
    expect(
      lentReminderMessage(loan(due: CalendarDate(2026, 11, 30)), today: today),
      'Hi John, hope you are well. A gentle reminder about the KES 5,000 '
      'I lent you on 3 Oct. We agreed on 30 Nov. '
      'Let me know when works for you. Thanks!',
    );
  });

  test('the reminder thanks them for part payments', () {
    final message = lentReminderMessage(
      loan(due: CalendarDate(2026, 10, 31), payments: part),
      today: today,
    );
    expect(message, contains('Thank you for the KES 2,000 so far'));
    expect(message, contains('KES 3,000 is left'));
    expect(message, contains('We had agreed on 31 Oct.'));
  });
}
