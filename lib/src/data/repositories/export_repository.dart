import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/export/export_tables.dart';
import '../../domain/payees/payee_identifier.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Reads everything exports need, with names already looked up.
abstract interface class ExportRepository {
  /// Transactions, oldest first, narrowed by any filter given: time in
  /// `[from, to)`, carrying [tagId], on [accountId] or with [payeeId].
  Future<List<ExportTransaction>> transactions({
    DateTime? from,
    DateTime? to,
    int? tagId,
    int? accountId,
    int? payeeId,
  });

  Future<List<ExportPayee>> payees();

  Future<List<ExportCategory>> categories();

  Future<List<({String name, int count})>> tags();

  Future<List<ExportAccount>> accounts();

  /// Category names by id.
  Future<Map<int, String>> categoryNames();

  /// Tag names by id.
  Future<Map<int, String>> tagNames();
}

class DriftExportRepository implements ExportRepository {
  DriftExportRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<ExportTransaction>> transactions({
    DateTime? from,
    DateTime? to,
    int? tagId,
    int? accountId,
    int? payeeId,
  }) async {
    final t = _db.transactions;
    final links = _db.transactionTags;
    Expression<bool> where = const Constant(true);
    if (from != null) where &= t.occurredAt.isBiggerOrEqualValue(from);
    if (to != null) where &= t.occurredAt.isSmallerThanValue(to);
    if (accountId != null) where &= t.accountId.equals(accountId);
    if (payeeId != null) where &= t.payeeId.equals(payeeId);
    if (tagId != null) {
      where &= existsQuery(
        _db.select(links)..where(
          (l) => l.transactionId.equalsExp(t.id) & l.tagId.equals(tagId),
        ),
      );
    }

    final categories = await categoryNames();
    final tagNamesById = await tagNames();
    final tagsByTransaction = <int, List<String>>{};
    final tagRows = await (_db.select(links).join([
      innerJoin(t, t.id.equalsExp(links.transactionId)),
    ])..where(where)).map((row) => row.readTable(links)).get();
    for (final link in tagRows) {
      final name = tagNamesById[link.tagId];
      if (name != null) {
        (tagsByTransaction[link.transactionId] ??= []).add(name);
      }
    }

    final query =
        _db.select(t).join([
            innerJoin(_db.accounts, _db.accounts.id.equalsExp(t.accountId)),
            leftOuterJoin(_db.payees, _db.payees.id.equalsExp(t.payeeId)),
          ])
          ..where(where)
          ..orderBy([OrderingTerm.asc(t.occurredAt), OrderingTerm.asc(t.id)]);
    return [
      for (final row in await query.get())
        () {
          final r = row.readTable(t);
          final payee = row.readTableOrNull(_db.payees);
          final categoryId = r.categoryOverrideId ?? payee?.defaultCategoryId;
          final kind = r.counterpartyKind;
          final value = r.counterpartyValue;
          return ExportTransaction(
            id: r.id,
            occurredAt: r.occurredAt,
            accountName: row.readTable(_db.accounts).name,
            amountMinor: r.amountMinor,
            direction: r.direction,
            kind: r.kind ?? TransactionKind.bank,
            source: r.source,
            currency: r.currency,
            feeMinor: r.feeMinor,
            payeeName: payee?.displayName,
            counterpartyName: r.counterpartyName,
            counterpartyValue: kind == null || value == null
                ? null
                : PayeeIdentifier.stored(kind, value).label,
            categoryName: categoryId == null ? null : categories[categoryId],
            leakType: payee?.leakType ?? LeakType.none,
            tags: (tagsByTransaction[r.id] ?? [])..sort(),
            receiptNo: r.receiptNo,
            isOwnTransfer: r.transferPairId != null,
          );
        }(),
    ];
  }

  @override
  Future<List<ExportPayee>> payees() async {
    final p = _db.payees;
    final t = _db.transactions;
    final count = t.id.count();
    final categories = await categoryNames();
    final identifiers = <int, List<String>>{};
    for (final row in await _db.select(_db.payeeIdentifiers).get()) {
      (identifiers[row.payeeId] ??= []).add(
        PayeeIdentifier.stored(row.kind, row.value).label,
      );
    }
    final query =
        _db.select(p).join([leftOuterJoin(t, t.payeeId.equalsExp(p.id))])
          ..addColumns([count])
          ..groupBy([p.id])
          ..orderBy([OrderingTerm.asc(p.displayName.collate(Collate.noCase))]);
    return [
      for (final row in await query.get())
        (
          name: row.readTable(p).displayName,
          identifiers: identifiers[row.readTable(p).id] ?? const [],
          categoryName: categories[row.readTable(p).defaultCategoryId],
          leakType: row.readTable(p).leakType,
          transactionCount: row.read(count)!,
        ),
    ];
  }

  @override
  Future<List<ExportCategory>> categories() async => [
    for (final c in await (_db.select(
      _db.categories,
    )..orderBy([(c) => OrderingTerm.asc(c.name)])).get())
      (
        name: c.name,
        type: c.type,
        isDailySpending: c.isDailySpending,
        isOwn: c.key == null,
      ),
  ];

  @override
  Future<List<({String name, int count})>> tags() async {
    final links = _db.transactionTags;
    final count = links.transactionId.count();
    final query =
        _db.select(_db.tags).join([
            leftOuterJoin(links, links.tagId.equalsExp(_db.tags.id)),
          ])
          ..addColumns([count])
          ..groupBy([_db.tags.id])
          ..orderBy([OrderingTerm.asc(_db.tags.name)]);
    return [
      for (final row in await query.get())
        (name: row.readTable(_db.tags).name, count: row.read(count)!),
    ];
  }

  @override
  Future<List<ExportAccount>> accounts() async => [
    for (final a in await (_db.select(
      _db.accounts,
    )..orderBy([(a) => OrderingTerm.asc(a.name)])).get())
      (
        name: a.name,
        type: a.type,
        currency: a.currency,
        openingBalanceMinor: a.openingBalanceMinor,
        openingDate: a.openingDate,
      ),
  ];

  @override
  Future<Map<int, String>> categoryNames() async => {
    for (final c in await _db.select(_db.categories).get()) c.id: c.name,
  };

  @override
  Future<Map<int, String>> tagNames() async => {
    for (final t in await _db.select(_db.tags).get()) t.id: t.name,
  };
}

final exportRepositoryProvider = Provider<ExportRepository>(
  (ref) => DriftExportRepository(ref.watch(appDatabaseProvider)),
);
