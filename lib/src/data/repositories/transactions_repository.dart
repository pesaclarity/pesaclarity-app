import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ledger/ledger_entry.dart';
import '../../domain/ledger/own_transfers.dart';
import '../../domain/payees/payee_directory.dart';
import '../../domain/payees/payee_identifier.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';
import 'payees_repository.dart';

/// The ledger of transactions from SMS, statements and manual entry.
abstract interface class TransactionsRepository {
  /// Most recent first; only those tagged [tagId] when given.
  Stream<List<TransactionRecord>> watchRecent({int limit = 50, int? tagId});

  /// Stores [transaction]. Without a payee id, a counterparty (normalised
  /// with `PayeeIdentifier`) is resolved to its named payee, if any.
  Future<int> add(TransactionsCompanion transaction);

  /// Finds an existing transaction with the same receipt, for dedupe between
  /// SMS and later statement imports.
  Future<TransactionRecord?> findByReceipt(int accountId, String receiptNo);

  /// Transactions with time in `[from, to)` as ledger entries, oldest first,
  /// with their payee applied (see `applyPayee`) and their tags. Only those
  /// tagged [tagId] when given.
  Future<List<LedgerEntry>> ledgerEntries({
    required DateTime from,
    required DateTime to,
    int? tagId,
  });

  /// Stores own-transfer pairs so both halves point at each other.
  Future<void> saveTransferPairs(Iterable<TransferPair> pairs);
}

class DriftTransactionsRepository implements TransactionsRepository {
  DriftTransactionsRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<TransactionRecord>> watchRecent({int limit = 50, int? tagId}) {
    final query = _db.select(_db.transactions)
      ..where((t) => tagId == null ? const Constant(true) : _hasTag(t, tagId))
      ..orderBy([
        (t) => OrderingTerm(expression: t.occurredAt, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    return query.watch();
  }

  @override
  Future<int> add(TransactionsCompanion transaction) async {
    final kind = transaction.counterpartyKind.value;
    final value = transaction.counterpartyValue.value;
    if (!transaction.payeeId.present && kind != null && value != null) {
      final payee = (await payeeDirectory(_db))
          .resolve(PayeeIdentifier.stored(kind, value));
      transaction = transaction.copyWith(payeeId: Value(payee?.id));
    }
    return _db.into(_db.transactions).insert(transaction);
  }

  Expression<bool> _hasTag($TransactionsTable t, int tagId) => existsQuery(
    _db.select(_db.transactionTags)
      ..where((l) => l.transactionId.equalsExp(t.id) & l.tagId.equals(tagId)),
  );

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
    int? tagId,
  }) async {
    final categories = {
      for (final c in await _db.select(_db.categories).get()) c.id: c,
    };
    final t = _db.transactions;
    final inRange =
        t.occurredAt.isBiggerOrEqualValue(from) &
        t.occurredAt.isSmallerThanValue(to);
    final query =
        _db.select(t).join([
            leftOuterJoin(_db.payees, _db.payees.id.equalsExp(t.payeeId)),
          ])
          ..where(tagId == null ? inRange : inRange & _hasTag(t, tagId))
          ..orderBy([OrderingTerm.asc(t.occurredAt), OrderingTerm.asc(t.id)]);

    final links = _db.transactionTags;
    final tagRows = await (_db.select(links).join([
      innerJoin(t, t.id.equalsExp(links.transactionId)),
    ])..where(inRange)).map((row) => row.readTable(links)).get();
    final tags = <int, Set<int>>{};
    for (final link in tagRows) {
      (tags[link.transactionId] ??= {}).add(link.tagId);
    }

    return [
      for (final row in await query.get())
        _toLedgerEntry(
          row.readTable(t),
          row.readTableOrNull(_db.payees),
          categories,
          tags,
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
  Map<int, Set<int>> tags,
) {
  final applied = applyPayee(
    payee == null
        ? null
        : PayeeRule(
            id: payee.id,
            displayName: payee.displayName,
            defaultCategoryId: payee.defaultCategoryId,
            leakType: payee.leakType,
          ),
    categoryOverrideId: record.categoryOverrideId,
  );
  final categoryId = applied.categoryId;
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
    payeeName: applied.displayName,
    leakType: applied.leakType,
    tagIds: tags[record.id] ?? const {},
  );
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => DriftTransactionsRepository(ref.watch(appDatabaseProvider)),
);
