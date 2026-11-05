import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../domain/books/books.dart';
import '../../domain/sales/sale_matching.dart';
import '../../domain/spaces/space_categories.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'category_seeds.dart';

/// One way a new sale is paid, and how much.
class SalePart {
  const SalePart(this.method, this.amountMinor)
    : assert(amountMinor > 0, 'parts are positive');

  final SalePaymentMethod method;
  final int amountMinor;
}

/// Who pays later for a credit part, and when they said they would.
class CreditTerms {
  const CreditTerms({required this.customer, this.dueDate});

  final String customer;
  final CalendarDate? dueDate;
}

/// Sales made with Sell, and how each was paid.
abstract interface class SalesRepository {
  /// Records a sale of [parts] at [at] and returns its id.
  ///
  /// Cash goes into [cashAccountId] as a sale. A credit part adds what
  /// [credit]'s customer owes. M-Pesa and bank parts wait for their payment
  /// messages, filed as sales by [link] once matched. [salesCategoryId] is the
  /// category sales are filed under.
  Future<int> record({
    required DateTime at,
    required List<SalePart> parts,
    required int salesCategoryId,
    required int cashAccountId,
    CreditTerms? credit,
    String? note,
    String? currency,
  });

  /// M-Pesa and bank parts still waiting for their message, oldest first,
  /// to be filed under [salesCategoryId] once matched.
  Future<List<WaitingPayment>> waiting({required int salesCategoryId});

  /// Transactions already paying for a sale.
  Future<Set<int>> linkedTransactions();

  /// Links a waiting part to the message [transactionId] that paid it, and
  /// files that message as a sale.
  Future<void> link(
    int paymentId,
    int transactionId, {
    required int salesCategoryId,
  });

  /// A waiting part was paid in cash after all.
  Future<void> paidInCash(
    int paymentId, {
    required DateTime at,
    required int salesCategoryId,
    required int cashAccountId,
  });

  /// Drops a waiting part, and its sale once nothing else is left of it.
  Future<void> removeWaiting(int paymentId);

  /// The credit parts of sales, for the books.
  Future<List<CreditSale>> creditSales({required int salesCategoryId});

  /// The Sales category, made with its key if the business has none.
  Future<int> salesCategoryId();
}

class DriftSalesRepository implements SalesRepository {
  DriftSalesRepository(this._db);

  final AppDatabase _db;

  @override
  Future<int> record({
    required DateTime at,
    required List<SalePart> parts,
    required int salesCategoryId,
    required int cashAccountId,
    CreditTerms? credit,
    String? note,
    String? currency,
  }) {
    assert(parts.isNotEmpty, 'a sale is paid somehow');
    final code = currency ?? BaseCurrency.code;
    return _db.transaction(() async {
      final saleId = await _db
          .into(_db.sales)
          .insert(
            SalesCompanion.insert(
              soldAt: at,
              totalMinor: parts.fold(0, (sum, p) => sum + p.amountMinor),
              currency: Value(code),
              note: Value(note),
            ),
          );
      for (final part in parts) {
        int? transactionId;
        int? loanId;
        switch (part.method) {
          case SalePaymentMethod.cash:
            transactionId = await _cashSale(
              at: at,
              amountMinor: part.amountMinor,
              currency: code,
              note: note,
              salesCategoryId: salesCategoryId,
              cashAccountId: cashAccountId,
            );
          case SalePaymentMethod.credit:
            final terms = credit;
            if (terms == null) {
              throw ArgumentError.notNull('credit');
            }
            loanId = await _db
                .into(_db.lentLoans)
                .insert(
                  LentLoansCompanion.insert(
                    person: terms.customer,
                    amountMinor: part.amountMinor,
                    currency: Value(code),
                    lentOn: CalendarDate.local(at).startInstant,
                    dueDate: Value(terms.dueDate?.startInstant),
                    note: Value(note ?? 'Sale'),
                  ),
                );
          case SalePaymentMethod.mpesa || SalePaymentMethod.bank:
            break;
        }
        await _db
            .into(_db.salePayments)
            .insert(
              SalePaymentsCompanion.insert(
                saleId: saleId,
                method: part.method,
                amountMinor: part.amountMinor,
                transactionId: Value(transactionId),
                lentLoanId: Value(loanId),
              ),
            );
      }
      return saleId;
    });
  }

  Future<int> _cashSale({
    required DateTime at,
    required int amountMinor,
    required String currency,
    required String? note,
    required int salesCategoryId,
    required int cashAccountId,
  }) => _db
      .into(_db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: cashAccountId,
          occurredAt: at,
          amountMinor: amountMinor,
          direction: TransactionDirection.inflow,
          currency: Value(currency),
          source: TransactionSource.manual,
          categoryOverrideId: Value(salesCategoryId),
          item: Value(note),
        ),
      );

  @override
  Future<List<WaitingPayment>> waiting({required int salesCategoryId}) async {
    final query =
        _db.select(_db.salePayments).join([
            innerJoin(
              _db.sales,
              _db.sales.id.equalsExp(_db.salePayments.saleId),
            ),
          ])
          ..where(
            _db.salePayments.transactionId.isNull() &
                _db.salePayments.method.isInValues([
                  SalePaymentMethod.mpesa,
                  SalePaymentMethod.bank,
                ]),
          )
          ..orderBy([OrderingTerm(expression: _db.sales.soldAt)]);
    return [
      for (final row in await query.get())
        WaitingPayment(
          id: row.readTable(_db.salePayments).id,
          kind: WaitingKind.sale,
          method: row.readTable(_db.salePayments).method,
          amountMinor: row.readTable(_db.salePayments).amountMinor,
          currency: row.readTable(_db.sales).currency,
          at: row.readTable(_db.sales).soldAt,
          categoryId: salesCategoryId,
          note: row.readTable(_db.sales).note,
        ),
    ];
  }

  @override
  Future<Set<int>> linkedTransactions() async => {
    for (final p in await (_db.select(
      _db.salePayments,
    )..where((p) => p.transactionId.isNotNull())).get())
      p.transactionId!,
  };

  @override
  Future<void> link(
    int paymentId,
    int transactionId, {
    required int salesCategoryId,
  }) => _db.transaction(() async {
    await (_db.update(_db.salePayments)..where((p) => p.id.equals(paymentId)))
        .write(SalePaymentsCompanion(transactionId: Value(transactionId)));
    await (_db.update(
      _db.transactions,
    )..where((t) => t.id.equals(transactionId))).write(
      TransactionsCompanion(categoryOverrideId: Value(salesCategoryId)),
    );
  });

  @override
  Future<void> paidInCash(
    int paymentId, {
    required DateTime at,
    required int salesCategoryId,
    required int cashAccountId,
  }) => _db.transaction(() async {
    final row = await _paymentWithSale(paymentId);
    if (row == null) return;
    final (payment, sale) = row;
    final transactionId = await _cashSale(
      at: at,
      amountMinor: payment.amountMinor,
      currency: sale.currency,
      note: sale.note,
      salesCategoryId: salesCategoryId,
      cashAccountId: cashAccountId,
    );
    await (_db.update(
      _db.salePayments,
    )..where((p) => p.id.equals(paymentId))).write(
      SalePaymentsCompanion(
        method: const Value(SalePaymentMethod.cash),
        transactionId: Value(transactionId),
      ),
    );
  });

  @override
  Future<void> removeWaiting(int paymentId) => _db.transaction(() async {
    final row = await _paymentWithSale(paymentId);
    if (row == null) return;
    final (payment, sale) = row;
    await (_db.delete(
      _db.salePayments,
    )..where((p) => p.id.equals(paymentId))).go();
    final left = await (_db.select(
      _db.salePayments,
    )..where((p) => p.saleId.equals(sale.id))).get();
    if (left.isEmpty) {
      await (_db.delete(_db.sales)..where((s) => s.id.equals(sale.id))).go();
    } else {
      await (_db.update(_db.sales)..where((s) => s.id.equals(sale.id))).write(
        SalesCompanion(
          totalMinor: Value(sale.totalMinor - payment.amountMinor),
        ),
      );
    }
  });

  Future<(SalePaymentRecord, SaleRecord)?> _paymentWithSale(
    int paymentId,
  ) async {
    final query = _db.select(_db.salePayments).join([
      innerJoin(_db.sales, _db.sales.id.equalsExp(_db.salePayments.saleId)),
    ])..where(_db.salePayments.id.equals(paymentId));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return (row.readTable(_db.salePayments), row.readTable(_db.sales));
  }

  @override
  Future<int> salesCategoryId() => ensureCategory(_db, salesSeed);

  @override
  Future<List<CreditSale>> creditSales({required int salesCategoryId}) async {
    final query =
        _db.select(_db.salePayments).join([
          innerJoin(_db.sales, _db.sales.id.equalsExp(_db.salePayments.saleId)),
        ])..where(
          _db.salePayments.method.equalsValue(SalePaymentMethod.credit) &
              _db.salePayments.lentLoanId.isNotNull(),
        );
    return [
      for (final row in await query.get())
        CreditSale(
          paymentId: row.readTable(_db.salePayments).id,
          at: row.readTable(_db.sales).soldAt,
          amountMinor: row.readTable(_db.salePayments).amountMinor,
          currency: row.readTable(_db.sales).currency,
          salesCategoryId: salesCategoryId,
        ),
    ];
  }
}

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => DriftSalesRepository(ref.watch(appDatabaseProvider)),
);
