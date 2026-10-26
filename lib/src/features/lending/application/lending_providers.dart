import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../data/repositories/lending_repository.dart';
import '../../../domain/debts/debt.dart';
import '../../../domain/debts/family_loan.dart';
import '../../../domain/lending/lent_loan.dart';
import '../../../domain/time/calendar.dart';

/// A family or friend loan the user owes, with where it stands.
class BorrowedLoan {
  const BorrowedLoan(this.debt, this.status);

  /// What is owed now, from the debt planner.
  final Debt debt;

  /// Agreed instalments and payments; drives the next due date and overdue.
  final FamilyLoanStatus status;

  bool get isCleared => debt.balanceMinor == 0;
}

/// Who owes whom among friends and family.
class LendingOverview {
  const LendingOverview({
    required this.today,
    required this.lent,
    required this.borrowed,
  });

  final CalendarDate today;

  /// Money the user lent, newest first.
  final List<LentLoan> lent;

  /// Family and friend loans the user owes, oldest first.
  final List<BorrowedLoan> borrowed;

  int get owedToYouMinor =>
      lent.fold(0, (sum, l) => sum + l.status(today).remainingMinor);

  int get youOweMinor =>
      borrowed.fold(0, (sum, b) => sum + b.debt.balanceMinor);

  bool get isEmpty => lent.isEmpty && borrowed.isEmpty;
}

final lendingOverviewProvider = FutureProvider<LendingOverview>((ref) async {
  final today = CalendarDate.nairobi(ref.watch(clockProvider)());
  final debts = ref.watch(debtsRepositoryProvider);
  final borrowed = <BorrowedLoan>[];
  for (final debt in await debts.debts(today: today)) {
    if (debt.isFormal) continue;
    final status = await debts.familyStatus(debt.id, today);
    if (status != null) borrowed.add(BorrowedLoan(debt, status));
  }
  return LendingOverview(
    today: today,
    lent: await ref.watch(lendingRepositoryProvider).lent(),
    borrowed: borrowed,
  );
});
