import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../domain/books/books.dart';
import '../../domain/people/people.dart';
import '../../domain/sales/sale_matching.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Bought, Got paid and Paid from a business's Today.
///
/// Cash takes effect at once, as an entry in the drawer. M-Pesa and bank
/// records wait for their payment message and take effect when [link]
/// matches it. Stock or a cost bought to pay later adds what the business
/// owes the supplier.
abstract interface class QuickRecordsRepository {
  /// Stock or a cost bought, filed under [categoryId]. With
  /// [SalePaymentMethod.credit], [supplier] is owed it, due [dueDate].
  Future<int> bought({
    required DateTime at,
    required int amountMinor,
    required SalePaymentMethod method,
    required int categoryId,
    required int cashAccountId,
    String? supplier,
    CalendarDate? dueDate,
    String? note,
    int? itemId,
  });

  /// Transactions that paid for stock bought to sell.
  Future<Set<int>> restockTransactions();

  /// [customer] paid [amountMinor] of what they owe, filed under
  /// [categoryId] (payments from customers).
  Future<int> gotPaid({
    required DateTime at,
    required int amountMinor,
    required SalePaymentMethod method,
    required String customer,
    required int categoryId,
    required int cashAccountId,
  });

  /// The business paid [amountMinor] of debt [debtId], filed under
  /// [categoryId] (payments to suppliers).
  Future<int> paid({
    required DateTime at,
    required int amountMinor,
    required SalePaymentMethod method,
    required int debtId,
    required String supplier,
    required int categoryId,
    required int cashAccountId,
  });

  /// The owner took [amountMinor] out for themselves, filed under
  /// [categoryId] (paid yourself).
  Future<int> paidYourself({
    required DateTime at,
    required int amountMinor,
    required SalePaymentMethod method,
    required int categoryId,
    required int cashAccountId,
  });

  /// Change of [amountMinor] given back to a customer who paid too much,
  /// filed under [salesCategoryId] as money back on a sale.
  Future<int> change({
    required DateTime at,
    required int amountMinor,
    required SalePaymentMethod method,
    required int salesCategoryId,
    required int cashAccountId,
    String? customer,
  });

  /// Records still waiting for their M-Pesa or bank message, oldest first.
  Future<List<WaitingPayment>> waiting();

  /// Transactions already linked to a record.
  Future<Set<int>> linkedTransactions();

  /// Links waiting record [recordId] to the message [transactionId] that
  /// paid it, and applies it.
  Future<void> link(int recordId, int transactionId);

  /// A waiting record was paid in cash after all.
  Future<void> paidInCash(
    int recordId, {
    required DateTime at,
    required int cashAccountId,
  });

  /// Drops a waiting record.
  Future<void> remove(int recordId);

  /// Stock and costs bought to pay later, for the books.
  Future<List<CreditPurchase>> creditPurchases();

  /// What customers and suppliers were owed before the records, for the
  /// books: lent loans that are not a sale's credit, and supplier debts not
  /// made by Bought, dated [suppliersAt] since a debt keeps no date.
  Future<List<OwedBefore>> owedBefore({required DateTime suppliersAt});

  /// What was bought from and paid to the supplier on [debtId], newest
  /// first. A debt not made by Bought starts with what was owed before.
  Future<List<StatementLine>> supplierHistory(
    int debtId, {
    required CalendarDate today,
  });

  /// Payments to suppliers that have gone through in `[from, to)`, newest
  /// first.
  Future<List<PaidRecord>> paidBetween({
    required DateTime from,
    required DateTime to,
  });
}

/// A payment made to a supplier.
class PaidRecord {
  const PaidRecord({
    required this.supplier,
    required this.amountMinor,
    required this.at,
    required this.method,
    this.debtId,
  });

  final String supplier;
  final int amountMinor;
  final DateTime at;
  final SalePaymentMethod method;
  final int? debtId;
}

class DriftQuickRecordsRepository implements QuickRecordsRepository {
  DriftQuickRecordsRepository(this._db);

  final AppDatabase _db;

  Future<int> _insert(QuickRecordsCompanion record) =>
      _db.into(_db.quickRecords).insert(record);

  @override
  Future<int> bought({
    required DateTime at,
    required int amountMinor,
    required SalePaymentMethod method,
    required int categoryId,
    required int cashAccountId,
    String? supplier,
    CalendarDate? dueDate,
    String? note,
    int? itemId,
  }) => _db.transaction(() async {
    int? debtId;
    if (method == SalePaymentMethod.credit) {
      final name = supplier?.trim() ?? '';
      if (name.isEmpty) throw ArgumentError.value(supplier, 'supplier');
      debtId = await _db
          .into(_db.debts)
          .insert(
            DebtsCompanion.insert(
              lender: name,
              type: DebtType.supplier,
              currency: Value(BaseCurrency.code),
              startingBalanceMinor: amountMinor,
              isFormal: const Value(false),
            ),
          );
      if (dueDate != null) {
        await _db
            .into(_db.debtInstalments)
            .insert(
              DebtInstalmentsCompanion.insert(
                debtId: debtId,
                dueDate: dueDate.startInstant,
                amountMinor: amountMinor,
              ),
            );
      }
    }
    final id = await _insert(
      QuickRecordsCompanion.insert(
        kind: QuickRecordKind.bought,
        at: at,
        amountMinor: amountMinor,
        currency: Value(BaseCurrency.code),
        method: method,
        categoryId: Value(categoryId),
        party: Value(supplier),
        note: Value(note),
        debtId: Value(debtId),
        itemId: Value(itemId),
      ),
    );
    if (method == SalePaymentMethod.cash) {
      await _payInCash(id, at: at, cashAccountId: cashAccountId);
    }
    return id;
  });

  @override
  Future<Set<int>> restockTransactions() async => {
    for (final r
        in await (_db.select(_db.quickRecords)..where(
              (r) =>
                  r.kind.equalsValue(QuickRecordKind.bought) &
                  r.itemId.isNotNull() &
                  r.transactionId.isNotNull(),
            ))
            .get())
      r.transactionId!,
  };

  @override
  Future<int> gotPaid({
    required DateTime at,
    required int amountMinor,
    required SalePaymentMethod method,
    required String customer,
    required int categoryId,
    required int cashAccountId,
  }) => _db.transaction(() async {
    final id = await _insert(
      QuickRecordsCompanion.insert(
        kind: QuickRecordKind.gotPaid,
        at: at,
        amountMinor: amountMinor,
        currency: Value(BaseCurrency.code),
        method: method,
        categoryId: Value(categoryId),
        party: Value(customer),
      ),
    );
    if (method == SalePaymentMethod.cash) {
      await _payInCash(id, at: at, cashAccountId: cashAccountId);
    }
    return id;
  });

  @override
  Future<int> paid({
    required DateTime at,
    required int amountMinor,
    required SalePaymentMethod method,
    required int debtId,
    required String supplier,
    required int categoryId,
    required int cashAccountId,
  }) => _db.transaction(() async {
    final id = await _insert(
      QuickRecordsCompanion.insert(
        kind: QuickRecordKind.paid,
        at: at,
        amountMinor: amountMinor,
        currency: Value(BaseCurrency.code),
        method: method,
        categoryId: Value(categoryId),
        party: Value(supplier),
        debtId: Value(debtId),
      ),
    );
    if (method == SalePaymentMethod.cash) {
      await _payInCash(id, at: at, cashAccountId: cashAccountId);
    }
    return id;
  });

  @override
  Future<int> paidYourself({
    required DateTime at,
    required int amountMinor,
    required SalePaymentMethod method,
    required int categoryId,
    required int cashAccountId,
  }) => _db.transaction(() async {
    final id = await _insert(
      QuickRecordsCompanion.insert(
        kind: QuickRecordKind.paidYourself,
        at: at,
        amountMinor: amountMinor,
        currency: Value(BaseCurrency.code),
        method: method,
        categoryId: Value(categoryId),
      ),
    );
    if (method == SalePaymentMethod.cash) {
      await _payInCash(id, at: at, cashAccountId: cashAccountId);
    }
    return id;
  });

  @override
  Future<int> change({
    required DateTime at,
    required int amountMinor,
    required SalePaymentMethod method,
    required int salesCategoryId,
    required int cashAccountId,
    String? customer,
  }) => _db.transaction(() async {
    final id = await _insert(
      QuickRecordsCompanion.insert(
        kind: QuickRecordKind.change,
        at: at,
        amountMinor: amountMinor,
        currency: Value(BaseCurrency.code),
        method: method,
        categoryId: Value(salesCategoryId),
        party: Value(customer),
        note: const Value('Change'),
      ),
    );
    if (method == SalePaymentMethod.cash) {
      await _payInCash(id, at: at, cashAccountId: cashAccountId);
    }
    return id;
  });

  Future<QuickRecord?> _record(int id) => (_db.select(
    _db.quickRecords,
  )..where((r) => r.id.equals(id))).getSingleOrNull();

  /// Makes the cash entry for record [id] and applies it.
  Future<void> _payInCash(
    int id, {
    required DateTime at,
    required int cashAccountId,
  }) async {
    final r = await _record(id);
    if (r == null) return;
    final transactionId = await _db
        .into(_db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: cashAccountId,
            occurredAt: at,
            amountMinor: r.amountMinor,
            direction: r.kind == QuickRecordKind.gotPaid
                ? TransactionDirection.inflow
                : TransactionDirection.outflow,
            currency: Value(r.currency),
            source: TransactionSource.manual,
            counterpartyName: Value(r.party),
            item: Value(r.note),
          ),
        );
    await _apply(r, transactionId);
  }

  /// Links [r] to [transactionId]: files it, ties a supplier payment to its
  /// debt, and takes a customer's payment off what they owe.
  Future<void> _apply(QuickRecord r, int transactionId) async {
    await (_db.update(_db.quickRecords)..where((q) => q.id.equals(r.id))).write(
      QuickRecordsCompanion(transactionId: Value(transactionId)),
    );
    await (_db.update(
      _db.transactions,
    )..where((t) => t.id.equals(transactionId))).write(
      TransactionsCompanion(
        categoryOverrideId: Value(r.categoryId),
        debtId: r.kind == QuickRecordKind.paid
            ? Value(r.debtId)
            : const Value.absent(),
        // Change given back takes money off the sale, not a cost.
        kind: r.kind == QuickRecordKind.change
            ? const Value(TransactionKind.reversal)
            : const Value.absent(),
      ),
    );
    if (r.kind == QuickRecordKind.gotPaid && r.party != null) {
      final paidAt = (await (_db.select(
        _db.transactions,
      )..where((t) => t.id.equals(transactionId))).getSingle()).occurredAt;
      await _takeOff(r.party!, r.amountMinor, paidAt);
    }
  }

  /// Records [amountMinor] against what [customer] owes, oldest first.
  Future<void> _takeOff(String customer, int amountMinor, DateTime at) async {
    final key = customer.trim().toLowerCase();
    final loans = [
      for (final l in await (_db.select(
        _db.lentLoans,
      )..orderBy([(l) => OrderingTerm.asc(l.lentOn)])).get())
        if (l.person.trim().toLowerCase() == key) l,
    ];
    final paid = <int, int>{};
    for (final p in await (_db.select(
      _db.loanPayments,
    )..where((p) => p.lentLoanId.isNotNull())).get()) {
      paid[p.lentLoanId!] = (paid[p.lentLoanId!] ?? 0) + p.amountMinor;
    }
    var left = amountMinor;
    for (final loan in loans) {
      if (left <= 0) break;
      final owed = loan.amountMinor - (paid[loan.id] ?? 0);
      if (owed <= 0) continue;
      final part = owed < left ? owed : left;
      await _db
          .into(_db.loanPayments)
          .insert(
            LoanPaymentsCompanion.insert(
              lentLoanId: Value(loan.id),
              paidOn: at,
              amountMinor: part,
            ),
          );
      left -= part;
    }
  }

  @override
  Future<List<WaitingPayment>> waiting() async => [
    for (final r
        in await (_db.select(_db.quickRecords)
              ..where(
                (r) =>
                    r.transactionId.isNull() &
                    r.categoryId.isNotNull() &
                    r.method.isInValues([
                      SalePaymentMethod.mpesa,
                      SalePaymentMethod.bank,
                    ]),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.at)]))
            .get())
      WaitingPayment(
        id: r.id,
        kind: switch (r.kind) {
          QuickRecordKind.bought => WaitingKind.bought,
          QuickRecordKind.gotPaid => WaitingKind.gotPaid,
          QuickRecordKind.paid => WaitingKind.paid,
          QuickRecordKind.paidYourself => WaitingKind.paidYourself,
          QuickRecordKind.change => WaitingKind.change,
        },
        method: r.method,
        amountMinor: r.amountMinor,
        currency: r.currency,
        at: r.at,
        categoryId: r.categoryId!,
        note: r.note,
        party: r.party,
      ),
  ];

  @override
  Future<Set<int>> linkedTransactions() async => {
    for (final r in await (_db.select(
      _db.quickRecords,
    )..where((r) => r.transactionId.isNotNull())).get())
      r.transactionId!,
  };

  @override
  Future<void> link(int recordId, int transactionId) =>
      _db.transaction(() async {
        final r = await _record(recordId);
        if (r == null || r.transactionId != null) return;
        await _apply(r, transactionId);
      });

  @override
  Future<void> paidInCash(
    int recordId, {
    required DateTime at,
    required int cashAccountId,
  }) => _db.transaction(() async {
    await (_db.update(
      _db.quickRecords,
    )..where((r) => r.id.equals(recordId))).write(
      const QuickRecordsCompanion(method: Value(SalePaymentMethod.cash)),
    );
    await _payInCash(recordId, at: at, cashAccountId: cashAccountId);
  });

  @override
  Future<void> remove(int recordId) =>
      (_db.delete(_db.quickRecords)..where((r) => r.id.equals(recordId))).go();

  @override
  Future<List<CreditPurchase>> creditPurchases() async => [
    for (final r
        in await (_db.select(_db.quickRecords)..where(
              (r) =>
                  r.kind.equalsValue(QuickRecordKind.bought) &
                  r.method.equalsValue(SalePaymentMethod.credit) &
                  r.debtId.isNotNull() &
                  r.categoryId.isNotNull(),
            ))
            .get())
      CreditPurchase(
        recordId: r.id,
        at: r.at,
        amountMinor: r.amountMinor,
        currency: r.currency,
        categoryId: r.categoryId!,
      ),
  ];

  @override
  Future<List<PaidRecord>> paidBetween({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final r
        in await (_db.select(_db.quickRecords)
              ..where(
                (r) =>
                    r.kind.equalsValue(QuickRecordKind.paid) &
                    r.transactionId.isNotNull() &
                    r.at.isBiggerOrEqualValue(from) &
                    r.at.isSmallerThanValue(to),
              )
              ..orderBy([(r) => OrderingTerm.desc(r.at)]))
            .get())
      PaidRecord(
        supplier: r.party ?? 'Supplier',
        amountMinor: r.amountMinor,
        at: r.at,
        method: r.method,
        debtId: r.debtId,
      ),
  ];

  @override
  Future<List<StatementLine>> supplierHistory(
    int debtId, {
    required CalendarDate today,
  }) async {
    final debt = await (_db.select(
      _db.debts,
    )..where((d) => d.id.equals(debtId))).getSingleOrNull();
    if (debt == null) return const [];
    final records = await (_db.select(
      _db.quickRecords,
    )..where((r) => r.debtId.equals(debtId))).get();
    final lines = <StatementLine>[
      for (final r in records)
        if (r.kind == QuickRecordKind.bought)
          StatementLine(
            date: CalendarDate.local(r.at),
            label: r.note == null ? 'Bought on credit' : '${r.note} on credit',
            amountMinor: r.amountMinor,
          )
        else if (r.transactionId != null)
          StatementLine(
            date: CalendarDate.local(r.at),
            label: 'Paid',
            amountMinor: -r.amountMinor,
          ),
    ];
    final linked = {for (final r in records) ?r.transactionId};
    for (final t
        in await (_db.select(_db.transactions)..where(
              (t) =>
                  t.debtId.equals(debtId) &
                  t.direction.equalsValue(TransactionDirection.outflow),
            ))
            .get()) {
      if (linked.contains(t.id)) continue;
      lines.add(
        StatementLine(
          date: CalendarDate.local(t.occurredAt),
          label: 'Paid',
          amountMinor: -t.amountMinor,
        ),
      );
    }
    for (final p in await (_db.select(
      _db.loanPayments,
    )..where((p) => p.debtId.equals(debtId))).get()) {
      lines.add(
        StatementLine(
          date: CalendarDate.local(p.paidOn),
          label: 'Paid',
          amountMinor: -p.amountMinor,
        ),
      );
    }
    if (!records.any((r) => r.kind == QuickRecordKind.bought)) {
      final first = lines.isEmpty
          ? null
          : lines.map((l) => l.date).reduce((a, b) => a.isBefore(b) ? a : b);
      lines.add(
        StatementLine(
          date: first ?? today,
          label: 'Owed before',
          amountMinor: debt.startingBalanceMinor,
        ),
      );
    }
    lines.sort((a, b) => b.date.compareTo(a.date));
    return lines;
  }

  @override
  Future<List<OwedBefore>> owedBefore({required DateTime suppliersAt}) async {
    final fromSales = {
      for (final p in await (_db.select(
        _db.salePayments,
      )..where((p) => p.lentLoanId.isNotNull())).get())
        p.lentLoanId!,
    };
    final fromBought = {
      for (final r
          in await (_db.select(_db.quickRecords)..where(
                (r) =>
                    r.kind.equalsValue(QuickRecordKind.bought) &
                    r.debtId.isNotNull(),
              ))
              .get())
        r.debtId!,
    };
    return [
      for (final l in await _db.select(_db.lentLoans).get())
        if (!fromSales.contains(l.id))
          OwedBefore(
            sourceId: l.id,
            at: l.lentOn,
            amountMinor: l.amountMinor,
            currency: l.currency,
            toYou: true,
          ),
      for (final d in await (_db.select(
        _db.debts,
      )..where((d) => d.type.equalsValue(DebtType.supplier))).get())
        if (!fromBought.contains(d.id))
          OwedBefore(
            sourceId: d.id,
            at: suppliersAt,
            amountMinor: d.startingBalanceMinor,
            currency: d.currency,
            toYou: false,
          ),
    ];
  }
}

final quickRecordsRepositoryProvider = Provider<QuickRecordsRepository>(
  (ref) => DriftQuickRecordsRepository(ref.watch(appDatabaseProvider)),
);
