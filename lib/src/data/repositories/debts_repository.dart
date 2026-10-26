import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/debts/debt.dart';
import '../../domain/debts/family_loan.dart';
import '../../domain/debts/repayment_matcher.dart';
import '../../domain/payees/payee_identifier.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'transactions_repository.dart';

/// Debts, their agreed instalments and the repayments linked to them.
abstract interface class DebtsRepository {
  Future<int> add(DebtsCompanion debt);

  Future<void> remove(int debtId);

  /// Records a balance the user confirmed on [asOf], such as from a lender
  /// statement. Repayments after it come off it.
  Future<void> confirmBalance(int debtId, int balanceMinor, DateTime asOf);

  /// Replaces the instalments agreed on a family or friend loan.
  Future<void> setInstalments(int debtId, Iterable<DebtInstalment> agreed);

  /// Stores the user's own payoff order; debts left out lose their place.
  Future<void> setCustomOrder(List<int> debtIds);

  Future<List<int>> customOrder();

  /// Links a transaction to the debt it repays, once the user confirms.
  Future<void> linkRepayment(int transactionId, int debtId);

  /// Every debt with what is owed now: the confirmed balance, or else the
  /// starting balance, less the repayments linked since. Family loans carry
  /// the instalments still to pay as of [today].
  Future<List<Debt>> debts({required CalendarDate today});

  /// Where a family or friend loan stands. Null for an unknown debt.
  Future<FamilyLoanStatus?> familyStatus(int debtId, CalendarDate today);

  /// Suggests which debt each unlinked payment in `[from, to)` repays.
  Future<List<RepaymentSuggestion>> repaymentSuggestions({
    required DateTime from,
    required DateTime to,
    required CalendarDate today,
  });
}

class DriftDebtsRepository implements DebtsRepository {
  DriftDebtsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<int> add(DebtsCompanion debt) => _db.into(_db.debts).insert(debt);

  @override
  Future<void> remove(int debtId) => _db.transaction(() async {
    await (_db.update(_db.transactions)..where((t) => t.debtId.equals(debtId)))
        .write(const TransactionsCompanion(debtId: Value(null)));
    await (_db.delete(_db.debts)..where((d) => d.id.equals(debtId))).go();
  });

  @override
  Future<void> confirmBalance(int debtId, int balanceMinor, DateTime asOf) =>
      (_db.update(_db.debts)..where((d) => d.id.equals(debtId))).write(
        DebtsCompanion(
          balanceMinor: Value(balanceMinor),
          balanceAsOf: Value(asOf),
        ),
      );

  @override
  Future<void> setInstalments(int debtId, Iterable<DebtInstalment> agreed) =>
      _db.transaction(() async {
        await (_db.delete(
          _db.debtInstalments,
        )..where((i) => i.debtId.equals(debtId))).go();
        for (final instalment in agreed) {
          await _db
              .into(_db.debtInstalments)
              .insert(
                DebtInstalmentsCompanion.insert(
                  debtId: debtId,
                  dueDate: instalment.dueDate.startInstant,
                  amountMinor: instalment.amountMinor,
                ),
              );
        }
      });

  @override
  Future<void> setCustomOrder(List<int> debtIds) => _db.transaction(() async {
    await _db
        .update(_db.debts)
        .write(const DebtsCompanion(customOrder: Value(null)));
    for (var i = 0; i < debtIds.length; i++) {
      await (_db.update(_db.debts)..where((d) => d.id.equals(debtIds[i])))
          .write(DebtsCompanion(customOrder: Value(i)));
    }
  });

  @override
  Future<List<int>> customOrder() async {
    final rows =
        await (_db.select(_db.debts)
              ..where((d) => d.customOrder.isNotNull())
              ..orderBy([(d) => OrderingTerm.asc(d.customOrder)]))
            .get();
    return [for (final r in rows) r.id];
  }

  @override
  Future<void> linkRepayment(int transactionId, int debtId) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(transactionId)))
          .write(TransactionsCompanion(debtId: Value(debtId)));

  @override
  Future<List<Debt>> debts({required CalendarDate today}) async {
    final rows = await (_db.select(
      _db.debts,
    )..orderBy([(d) => OrderingTerm.asc(d.id)])).get();
    final instalments = await _instalmentsByDebt();
    final repayments = await _repaymentsByDebt();
    final identifiers = await _identifiersByPayee();

    return [
      for (final row in rows)
        _toDebt(
          row,
          agreed: instalments[row.id] ?? const [],
          repayments: repayments[row.id] ?? const [],
          identifiers: row.payeeId == null
              ? const []
              : identifiers[row.payeeId] ?? const [],
          today: today,
        ),
    ];
  }

  @override
  Future<FamilyLoanStatus?> familyStatus(int debtId, CalendarDate today) async {
    final row = await (_db.select(
      _db.debts,
    )..where((d) => d.id.equals(debtId))).getSingleOrNull();
    if (row == null) return null;
    return FamilyLoanStatus.of(
      amountMinor: row.startingBalanceMinor,
      agreed: (await _instalmentsByDebt())[debtId] ?? const [],
      payments: _loanPayments((await _repaymentsByDebt())[debtId] ?? const []),
      today: today,
    );
  }

  @override
  Future<List<RepaymentSuggestion>> repaymentSuggestions({
    required DateTime from,
    required DateTime to,
    required CalendarDate today,
  }) async {
    final entries = await DriftTransactionsRepository(_db)
        .ledgerEntries(from: from, to: to);
    final t = _db.transactions;
    final records = {
      for (final r
          in await (_db.select(t)..where(
                (t) =>
                    t.occurredAt.isBiggerOrEqualValue(from) &
                    t.occurredAt.isSmallerThanValue(to),
              ))
              .get())
        r.id: r,
    };
    return suggestRepayments(
      debts: await debts(today: today),
      candidates: [
        for (final entry in entries)
          RepaymentCandidate(
            entry,
            counterparty: _counterparty(records[entry.id]),
          ),
      ],
      linkedEntryIds: {
        for (final r in records.values)
          if (r.debtId != null) r.id,
      },
    );
  }

  Future<Map<int, List<DebtInstalment>>> _instalmentsByDebt() async {
    final byDebt = <int, List<DebtInstalment>>{};
    for (final row in await _db.select(_db.debtInstalments).get()) {
      (byDebt[row.debtId] ??= []).add(
        DebtInstalment(
          dueDate: CalendarDate.nairobi(row.dueDate),
          amountMinor: row.amountMinor,
        ),
      );
    }
    return byDebt;
  }

  /// Outflows linked to each debt, oldest first.
  Future<Map<int, List<TransactionRecord>>> _repaymentsByDebt() async {
    final rows =
        await (_db.select(_db.transactions)
              ..where(
                (t) =>
                    t.debtId.isNotNull() &
                    t.direction.equalsValue(TransactionDirection.outflow),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
            .get();
    final byDebt = <int, List<TransactionRecord>>{};
    for (final row in rows) {
      (byDebt[row.debtId!] ??= []).add(row);
    }
    return byDebt;
  }

  Future<Map<int, List<PayeeIdentifier>>> _identifiersByPayee() async {
    final byPayee = <int, List<PayeeIdentifier>>{};
    for (final row in await _db.select(_db.payeeIdentifiers).get()) {
      (byPayee[row.payeeId] ??= []).add(
        PayeeIdentifier.stored(row.kind, row.value),
      );
    }
    return byPayee;
  }
}

Debt _toDebt(
  DebtRecord row, {
  required List<DebtInstalment> agreed,
  required List<TransactionRecord> repayments,
  required List<PayeeIdentifier> identifiers,
  required CalendarDate today,
}) {
  final asOf = row.balanceAsOf;
  final base = row.balanceMinor ?? row.startingBalanceMinor;
  final repaid = repayments
      .where((r) => asOf == null || !r.occurredAt.isBefore(asOf))
      .fold(0, (sum, r) => sum + r.amountMinor);
  final owed = base > repaid ? base - repaid : 0;

  final remainingInstalments = agreed.isEmpty
      ? const <DebtInstalment>[]
      : FamilyLoanStatus.of(
          amountMinor: row.startingBalanceMinor,
          agreed: agreed,
          payments: _loanPayments(repayments),
          today: today,
        ).remainingInstalments;

  return Debt(
    id: row.id,
    lender: row.lender,
    type: row.type,
    balanceMinor: owed,
    currency: row.currency,
    annualRateBasisPoints: row.annualRateBasisPoints ?? 0,
    minimumPaymentMinor: row.minimumPaymentMinor,
    isFormal: row.isFormal,
    instalments: remainingInstalments,
    payeeId: row.payeeId,
    identifiers: identifiers,
  );
}

List<LoanPayment> _loanPayments(List<TransactionRecord> repayments) => [
  for (final r in repayments)
    LoanPayment(
      date: CalendarDate.nairobi(r.occurredAt),
      amountMinor: r.amountMinor,
    ),
];

PayeeIdentifier? _counterparty(TransactionRecord? record) {
  final kind = record?.counterpartyKind;
  final value = record?.counterpartyValue;
  if (kind == null || value == null) return null;
  return PayeeIdentifier.stored(kind, value);
}

final debtsRepositoryProvider = Provider<DebtsRepository>(
  (ref) => DriftDebtsRepository(ref.watch(appDatabaseProvider)),
);
