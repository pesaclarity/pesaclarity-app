import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ledger/ledger_entry.dart';
import '../../domain/ledger/own_transfers.dart';
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

  /// Transactions with time in `[from, to)` as ledger entries, oldest first,
  /// each with its category resolved from the override or else the payee.
  Future<List<LedgerEntry>> ledgerEntries({
    required DateTime from,
    required DateTime to,
  });

  /// Stores own-transfer pairs so both halves point at each other.
  Future<void> saveTransferPairs(Iterable<TransferPair> pairs);
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

  @override
  Future<List<LedgerEntry>> ledgerEntries({
    required DateTime from,
    required DateTime to,
  }) async {
    final categories = {
      for (final c in await _db.select(_db.categories).get()) c.id: c,
    };
    final t = _db.transactions;
    final query =
        _db.select(t).join([
            leftOuterJoin(_db.payees, _db.payees.id.equalsExp(t.payeeId)),
          ])
          ..where(
            t.occurredAt.isBiggerOrEqualValue(from) &
                t.occurredAt.isSmallerThanValue(to),
          )
          ..orderBy([OrderingTerm.asc(t.occurredAt), OrderingTerm.asc(t.id)]);

    return [
      for (final row in await query.get())
        _toLedgerEntry(
          row.readTable(t),
          row.readTableOrNull(_db.payees),
          categories,
        ),
    ];
  }

  @override
  Future<void> saveTransferPairs(Iterable<TransferPair> pairs) =>
      _db.transaction(() async {
        for (final pair in pairs) {
          await _setPair(pair.outflowId, pair.inflowId);
          await _setPair(pair.inflowId, pair.outflowId);
        }
      });

  Future<void> _setPair(int id, int partnerId) =>
      (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
        TransactionsCompanion(transferPairId: Value(partnerId)),
      );
}

LedgerEntry _toLedgerEntry(
  TransactionRecord record,
  Payee? payee,
  Map<int, Category> categories,
) {
  final categoryId = record.categoryOverrideId ?? payee?.defaultCategoryId;
  final category = categoryId == null ? null : categories[categoryId];
  return LedgerEntry(
    id: record.id,
    accountId: record.accountId,
    occurredAt: record.occurredAt,
    amountMinor: record.amountMinor,
    direction: record.direction,
    kind: record.kind ?? TransactionKind.bank,
    currency: record.currency,
    feeMinor: record.feeMinor,
    payeeId: record.payeeId,
    categoryId: categoryId,
    categoryType: category?.type,
    isDailySpending: category?.isDailySpending ?? false,
    transferPairId: record.transferPairId,
  );
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => DriftTransactionsRepository(ref.watch(appDatabaseProvider)),
);
