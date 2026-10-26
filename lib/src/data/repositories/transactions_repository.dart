import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';

/// The ledger of transactions from SMS, statements and manual entry.
abstract interface class TransactionsRepository {
  /// Most recent first.
  Stream<List<TransactionRecord>> watchRecent({int limit = 50});

  Future<int> add(TransactionsCompanion transaction);

  /// Finds an existing transaction with the same receipt, for dedupe between
  /// SMS and later statement imports.
  Future<TransactionRecord?> findByReceipt(int accountId, String receiptNo);
}

class DriftTransactionsRepository implements TransactionsRepository {
  DriftTransactionsRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<TransactionRecord>> watchRecent({int limit = 50}) {
    final query = _db.select(_db.transactions)
      ..orderBy([
        (t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return query.watch();
  }

  @override
  Future<int> add(TransactionsCompanion transaction) =>
      _db.into(_db.transactions).insert(transaction);

  @override
  Future<TransactionRecord?> findByReceipt(int accountId, String receiptNo) {
    final query = _db.select(_db.transactions)
      ..where(
        (t) => t.accountId.equals(accountId) & t.receiptNo.equals(receiptNo),
      )
      ..limit(1);
    return query.getSingleOrNull();
  }
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => DriftTransactionsRepository(ref.watch(appDatabaseProvider)),
);
