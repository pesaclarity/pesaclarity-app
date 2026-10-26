import '../time/calendar.dart';
import 'debt.dart';

/// A part payment made on a family or friend loan.
class LoanPayment {
  const LoanPayment({required this.date, required this.amountMinor})
    : assert(amountMinor > 0, 'payments are positive');

  final CalendarDate date;
  final int amountMinor;
}

/// Where a family or friend loan stands: no interest, just what was agreed
/// and what has been paid.
///
/// Payments clear the oldest agreed instalment first, whenever they were
/// made, so paying early or in parts always counts.
class FamilyLoanStatus {
  const FamilyLoanStatus._({
    required this.amountMinor,
    required this.paidMinor,
    required this.overdueMinor,
    required this.remainingInstalments,
  });

  /// [amountMinor] is what was borrowed; [agreed] the instalments agreed,
  /// in any order.
  factory FamilyLoanStatus.of({
    required int amountMinor,
    required Iterable<DebtInstalment> agreed,
    required Iterable<LoanPayment> payments,
    required CalendarDate today,
  }) {
    final schedule = agreed.toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    var paid = payments.fold(0, (sum, p) => sum + p.amountMinor);
    final paidTotal = paid;

    final remaining = <DebtInstalment>[];
    var overdue = 0;
    for (final instalment in schedule) {
      final covered = paid < instalment.amountMinor
          ? paid
          : instalment.amountMinor;
      paid -= covered;
      final left = instalment.amountMinor - covered;
      if (left == 0) continue;
      remaining.add(
        DebtInstalment(dueDate: instalment.dueDate, amountMinor: left),
      );
      if (instalment.dueDate.isBefore(today)) overdue += left;
    }

    return FamilyLoanStatus._(
      amountMinor: amountMinor,
      paidMinor: paidTotal,
      overdueMinor: overdue,
      remainingInstalments: remaining,
    );
  }

  final int amountMinor;
  final int paidMinor;

  /// Agreed instalments due before today and not yet paid.
  final int overdueMinor;

  /// What is still to pay of each agreed instalment, oldest first. Feed these
  /// to [Debt.instalments] for the payoff plan.
  final List<DebtInstalment> remainingInstalments;

  int get remainingMinor =>
      paidMinor >= amountMinor ? 0 : amountMinor - paidMinor;

  bool get isCleared => remainingMinor == 0;

  /// The next instalment with something left to pay, overdue or not.
  DebtInstalment? get nextDue => remainingInstalments.firstOrNull;

  /// Owed but not covered by any agreed instalment, for a plan that does
  /// not add up to the loan.
  int get unscheduledMinor {
    final scheduled = remainingInstalments.fold(
      0,
      (sum, i) => sum + i.amountMinor,
    );
    return remainingMinor > scheduled ? remainingMinor - scheduled : 0;
  }
}
