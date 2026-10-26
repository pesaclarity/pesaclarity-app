import '../../core/money/money.dart';
import '../../core/money/money_format.dart';
import '../debts/debt.dart';
import '../debts/family_loan.dart';
import '../time/calendar.dart';
import '../time/date_labels.dart';

/// Money the user lent to a friend or relative, with the part payments they
/// have made back. No interest, like a family loan the user owes.
class LentLoan {
  const LentLoan({
    required this.id,
    required this.person,
    required this.amountMinor,
    required this.lentOn,
    this.dueDate,
    this.note,
    this.currency = 'KES',
    this.payments = const [],
  }) : assert(amountMinor > 0, 'loans are positive');

  final int id;
  final String person;
  final int amountMinor;
  final CalendarDate lentOn;

  /// When they agreed to pay it all back; null when no date was agreed.
  final CalendarDate? dueDate;
  final String? note;
  final String currency;
  final List<LoanPayment> payments;

  /// Where the loan stands on [today], with the due date as the one agreed
  /// instalment.
  FamilyLoanStatus status(CalendarDate today) => FamilyLoanStatus.of(
    amountMinor: amountMinor,
    agreed: [
      if (dueDate case final due?)
        DebtInstalment(dueDate: due, amountMinor: amountMinor),
    ],
    payments: payments,
    today: today,
  );

  /// Still owed at the start of [date]: nothing before it was lent.
  int outstandingAt(CalendarDate date) {
    if (!lentOn.isBefore(date)) return 0;
    final paid = payments
        .where((p) => p.date.isBefore(date))
        .fold(0, (sum, p) => sum + p.amountMinor);
    return paid >= amountMinor ? 0 : amountMinor - paid;
  }
}

/// A polite reminder for [loan], ready to send on WhatsApp.
String lentReminderMessage(LentLoan loan, {required CalendarDate today}) {
  final status = loan.status(today);
  String kes(int minor) => formatMoney(Money(minor, currency: loan.currency));
  String day(CalendarDate date) => dayLabel(date, thisYear: today.year);

  final firstName = loan.person.trim().split(RegExp(r'\s+')).first;
  final buffer = StringBuffer(
    'Hi $firstName, hope you are well. A gentle reminder about the '
    '${kes(loan.amountMinor)} I lent you on ${day(loan.lentOn)}.',
  );
  if (status.paidMinor > 0) {
    buffer.write(
      ' Thank you for the ${kes(status.paidMinor)} so far; '
      '${kes(status.remainingMinor)} is left.',
    );
  }
  final due = loan.dueDate;
  if (due != null) {
    buffer.write(
      due.isBefore(today)
          ? ' We had agreed on ${day(due)}.'
          : ' We agreed on ${day(due)}.',
    );
  }
  buffer.write(' Let me know when works for you. Thanks!');
  return buffer.toString();
}
