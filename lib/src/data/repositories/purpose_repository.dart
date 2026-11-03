import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/income/money_purpose.dart';
import '../../domain/payees/payee_directory.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'lending_repository.dart';

/// "What was this?" for money in from people whose money has meant
/// different things.
abstract interface class PurposeRepository {
  /// Notes that the person filed money in [transactionId] under
  /// [categoryId]. When that differs from what the payee's money was before,
  /// later money from them asks what it was for.
  Future<void> noteChoice(int transactionId, int categoryId);

  /// Files [transactionId] under [purpose]. With [alwaysUse], the payee
  /// takes that category and stops asking.
  ///
  /// A loan to you adds the payee to Debts when they are not there yet.
  /// Paying you back lowers the oldest money lent to someone of the payee's
  /// name that is still owed.
  Future<void> answer(
    int transactionId,
    MoneyPurpose purpose, {
    bool alwaysUse = false,
  });

  /// Whether money in from [payeeId] asks what it was for.
  Future<void> setAskPurpose(int payeeId, {required bool ask});
}

class DriftPurposeRepository implements PurposeRepository {
  DriftPurposeRepository(this._db);

  final AppDatabase _db;

  Future<TransactionRecord> _transaction(int id) =>
      (_db.select(_db.transactions)..where((t) => t.id.equals(id))).getSingle();

  Future<Payee?> _payee(int? id) => id == null
      ? Future.value()
      : (_db.select(
          _db.payees,
        )..where((p) => p.id.equals(id))).getSingleOrNull();

  @override
  Future<void> noteChoice(int transactionId, int categoryId) =>
      _db.transaction(() async {
        final tx = await _transaction(transactionId);
        final payee = await _payee(tx.payeeId);
        if (payee == null ||
            payee.askPurpose ||
            tx.direction != TransactionDirection.inflow) {
          return;
        }
        final t = _db.transactions;
        final earlier =
            await (_db.selectOnly(t, distinct: true)
                  ..addColumns([t.categoryOverrideId])
                  ..where(
                    t.payeeId.equals(payee.id) &
                        t.id.equals(transactionId).not() &
                        t.direction.equalsValue(TransactionDirection.inflow) &
                        t.categoryOverrideId.isNotNull(),
                  ))
                .map((row) => row.read(t.categoryOverrideId)!)
                .get();
        if (isMixedSender(
          chosenId: categoryId,
          payeeCategoryId: payee.defaultCategoryId,
          earlierIds: earlier,
        )) {
          await setAskPurpose(payee.id, ask: true);
        }
      });

  @override
  Future<void> answer(
    int transactionId,
    MoneyPurpose purpose, {
    bool alwaysUse = false,
  }) => _db.transaction(() async {
    final tx = await _transaction(transactionId);
    final payee = await _payee(tx.payeeId);
    final category = await (_db.select(
      _db.categories,
    )..where((c) => c.key.equals(purpose.categoryKey))).getSingleOrNull();
    await (_db.update(_db.transactions)
          ..where((t) => t.id.equals(transactionId)))
        .write(TransactionsCompanion(categoryOverrideId: Value(category?.id)));
    if (payee == null) return;
    if (alwaysUse) {
      await (_db.update(_db.payees)..where((p) => p.id.equals(payee.id))).write(
        PayeesCompanion(
          defaultCategoryId: Value(category?.id),
          askPurpose: const Value(false),
        ),
      );
    }
    switch (purpose) {
      case MoneyPurpose.loanToYou:
        await _addToDebts(payee, tx);
      case MoneyPurpose.payingBack:
        await _lowerLent(payee, tx);
      case MoneyPurpose.familySupport ||
          MoneyPurpose.work ||
          MoneyPurpose.gift ||
          MoneyPurpose.sale:
        break;
    }
  });

  Future<void> _addToDebts(Payee payee, TransactionRecord tx) async {
    final existing = await (_db.select(
      _db.debts,
    )..where((d) => d.payeeId.equals(payee.id))).get();
    if (existing.isNotEmpty) return;
    await _db
        .into(_db.debts)
        .insert(
          DebtsCompanion.insert(
            lender: payee.displayName,
            type: DebtType.family,
            currency: Value(tx.currency),
            startingBalanceMinor: tx.amountMinor,
            isFormal: const Value(false),
            payeeId: Value(payee.id),
          ),
        );
  }

  Future<void> _lowerLent(Payee payee, TransactionRecord tx) async {
    final paidOn = CalendarDate.local(tx.occurredAt);
    final name = payee.displayName.trim().toLowerCase();
    final lending = DriftLendingRepository(_db);
    final loans = await lending.lent();
    // Oldest first, so the earliest money lent is paid off first.
    for (final loan in loans.reversed) {
      if (loan.person.trim().toLowerCase() != name ||
          loan.currency != tx.currency) {
        continue;
      }
      final owed = loan.outstandingAt(paidOn);
      if (owed <= 0) continue;
      await lending.recordPayment(
        loan.id,
        tx.occurredAt,
        math.min(owed, tx.amountMinor),
      );
      return;
    }
  }

  @override
  Future<void> setAskPurpose(int payeeId, {required bool ask}) =>
      (_db.update(_db.payees)..where((p) => p.id.equals(payeeId))).write(
        PayeesCompanion(askPurpose: Value(ask)),
      );
}

final purposeRepositoryProvider = Provider<PurposeRepository>(
  (ref) => DriftPurposeRepository(ref.watch(appDatabaseProvider)),
);
