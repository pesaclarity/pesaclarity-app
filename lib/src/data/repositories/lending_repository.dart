import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../domain/debts/family_loan.dart';
import '../../domain/lending/lent_loan.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Money the user lent to friends and family, and what they paid back.
///
/// Money borrowed from friends and family is a family debt in
/// `DebtsRepository`.
abstract interface class LendingRepository {
  /// Every loan with its payments, newest first.
  Future<List<LentLoan>> lent();

  Future<int> add({
    required String person,
    required int amountMinor,
    required CalendarDate lentOn,
    CalendarDate? dueDate,
    String? note,
  });

  /// Saves [loan]'s person, amount, dates and note; payments are kept.
  Future<void> update(LentLoan loan);

  Future<void> recordPayment(int loanId, DateTime paidAt, int amountMinor);

  Future<void> remove(int loanId);
}

class DriftLendingRepository implements LendingRepository {
  DriftLendingRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<LentLoan>> lent() async {
    final rows =
        await (_db.select(_db.lentLoans)..orderBy([
              (l) => OrderingTerm.desc(l.lentOn),
              (l) => OrderingTerm.desc(l.id),
            ]))
            .get();
    final payments = <int, List<LoanPayment>>{};
    final paymentRows =
        await (_db.select(_db.loanPayments)
              ..where((p) => p.lentLoanId.isNotNull())
              ..orderBy([(p) => OrderingTerm.asc(p.paidOn)]))
            .get();
    for (final row in paymentRows) {
      (payments[row.lentLoanId!] ??= []).add(
        LoanPayment(
          date: CalendarDate.nairobi(row.paidOn),
          amountMinor: row.amountMinor,
        ),
      );
    }
    return [
      for (final row in rows)
        LentLoan(
          id: row.id,
          person: row.person,
          amountMinor: row.amountMinor,
          lentOn: CalendarDate.nairobi(row.lentOn),
          dueDate: row.dueDate == null
              ? null
              : CalendarDate.nairobi(row.dueDate!),
          note: row.note,
          currency: row.currency,
          payments: payments[row.id] ?? const [],
        ),
    ];
  }

  @override
  Future<int> add({
    required String person,
    required int amountMinor,
    required CalendarDate lentOn,
    CalendarDate? dueDate,
    String? note,
  }) => _db
      .into(_db.lentLoans)
      .insert(
        LentLoansCompanion.insert(
          person: person,
          amountMinor: amountMinor,
          currency: Value(BaseCurrency.code),
          lentOn: lentOn.startInstant,
          dueDate: Value(dueDate?.startInstant),
          note: Value(note),
        ),
      );

  @override
  Future<void> update(LentLoan loan) =>
      (_db.update(_db.lentLoans)..where((l) => l.id.equals(loan.id))).write(
        LentLoansCompanion(
          person: Value(loan.person),
          amountMinor: Value(loan.amountMinor),
          lentOn: Value(loan.lentOn.startInstant),
          dueDate: Value(loan.dueDate?.startInstant),
          note: Value(loan.note),
        ),
      );

  @override
  Future<void> recordPayment(int loanId, DateTime paidAt, int amountMinor) =>
      _db
          .into(_db.loanPayments)
          .insert(
            LoanPaymentsCompanion.insert(
              lentLoanId: Value(loanId),
              paidOn: paidAt,
              amountMinor: amountMinor,
            ),
          );

  @override
  Future<void> remove(int loanId) =>
      (_db.delete(_db.lentLoans)..where((l) => l.id.equals(loanId))).go();
}

final lendingRepositoryProvider = Provider<LendingRepository>(
  (ref) => DriftLendingRepository(ref.watch(appDatabaseProvider)),
);
