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

  /// Stores each of [transactions] whose account has no transaction with the
  /// same dedupe key yet, resolving payees like [add]. Returns how many were
  /// stored.
  Future<int> addNew(Iterable<TransactionsCompanion> transactions);

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

  /// Emits whenever something behind the ledger changes: transactions, their
  /// tags, payees, categories, accounts or the plan.
  Stream<void> watchChanges();

  /// One transaction with its account, payee and category, updating as any
  /// of them change. Emits null once the transaction is gone.
  Stream<TransactionDetail?> watchDetail(int id);
}

/// A transaction as its detail sheet shows it.
class TransactionDetail {
  const TransactionDetail({
    required this.record,
    required this.account,
    this.payee,
    this.category,
    this.payeeCategory,
  });

  final TransactionRecord record;
  final Account account;
  final Payee? payee;

  /// The override, or else the payee's default; null is Uncategorised.
  final Category? category;

  /// The payee's default category, which applies without an override.
  final Category? payeeCategory;

  bool get isCategoryOverridden => record.categoryOverrideId != null;

  /// The other party's raw identifier, for naming the payee.
  PayeeIdentifier? get counterparty {
    final kind = record.counterpartyKind;
    final value = record.counterpartyValue;
    return kind == null || value == null
        ? null
        : PayeeIdentifier.stored(kind, value);
  }
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
  Future<int> add(TransactionsCompanion transaction) async => _db
      .into(_db.transactions)
      .insert(_withPayee(transaction, await payeeDirectory(_db)));

  @override
  Future<int> addNew(Iterable<TransactionsCompanion> transactions) =>
      _db.transaction(() async {
        final directory = await payeeDirectory(_db);
        var added = 0;
        for (final transaction in transactions) {
          final key = transaction.dedupeKey.present
              ? transaction.dedupeKey.value
              : null;
          if (key != null && await _hasDedupeKey(transaction, key)) continue;
          await _db
              .into(_db.transactions)
              .insert(_withPayee(transaction, directory));
          added++;
        }
        return added;
      });

  Future<bool> _hasDedupeKey(TransactionsCompanion transaction, String key) =>
      (_db.selectOnly(_db.transactions)
            ..addColumns([_db.transactions.id])
            ..where(
              _db.transactions.accountId.equals(transaction.accountId.value) &
                  _db.transactions.dedupeKey.equals(key),
            )
            ..limit(1))
          .getSingleOrNull()
          .then((row) => row != null);

  TransactionsCompanion _withPayee(
    TransactionsCompanion transaction,
    PayeeDirectory directory,
  ) {
    final kind = transaction.counterpartyKind.present
        ? transaction.counterpartyKind.value
        : null;
    final value = transaction.counterpartyValue.present
        ? transaction.counterpartyValue.value
        : null;
    if (transaction.payeeId.present || kind == null || value == null) {
      return transaction;
    }
    final payee = directory.resolve(PayeeIdentifier.stored(kind, value));
    return transaction.copyWith(payeeId: Value(payee?.id));
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

  @override
  Stream<TransactionDetail?> watchDetail(int id) {
    final t = _db.transactions;
    final query = _db.select(t).join([
      innerJoin(_db.accounts, _db.accounts.id.equalsExp(t.accountId)),
      leftOuterJoin(_db.payees, _db.payees.id.equalsExp(t.payeeId)),
    ])..where(t.id.equals(id));
    return query.watchSingleOrNull().asyncMap((row) async {
      if (row == null) return null;
      final record = row.readTable(t);
      final payee = row.readTableOrNull(_db.payees);
      Future<Category?> category(int? id) => id == null
          ? Future.value()
          : (_db.select(
              _db.categories,
            )..where((c) => c.id.equals(id))).getSingleOrNull();
      final payeeCategory = await category(payee?.defaultCategoryId);
      return TransactionDetail(
        record: record,
        account: row.readTable(_db.accounts),
        payee: payee,
        payeeCategory: payeeCategory,
        category: record.categoryOverrideId == null
            ? payeeCategory
            : await category(record.categoryOverrideId),
      );
    });
  }

  @override
  Stream<void> watchChanges() => _db.tableUpdates(
    TableUpdateQuery.onAllTables([
      _db.transactions,
      _db.transactionTags,
      _db.payees,
      _db.payeeIdentifiers,
      _db.categories,
      _db.accounts,
      _db.recurring,
      _db.budgetItems,
    ]),
  );

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
    counterpartyName: record.counterpartyName,
    counterpartyKind: record.counterpartyKind,
    counterpartyValue: record.counterpartyValue,
    note: record.item,
  );
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => DriftTransactionsRepository(ref.watch(appDatabaseProvider)),
);

/// Counts changes to the ledger, so providers that read it with one-off
/// queries can watch this and recompute.
final ledgerChangesProvider = StreamProvider<int>((ref) async* {
  var count = 0;
  await for (final _
      in ref.watch(transactionsRepositoryProvider).watchChanges()) {
    yield ++count;
  }
});
