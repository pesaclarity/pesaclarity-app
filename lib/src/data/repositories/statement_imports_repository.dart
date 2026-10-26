import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Records of imported statements, and the ledger reads an import needs.
abstract interface class StatementImportsRepository {
  /// The earlier import of the file with SHA-256 [fileHash], if any.
  Future<Import?> findByHash(String fileHash);

  /// Stores the record of a finished import.
  Future<int> record(ImportsCompanion import);

  /// Every import, newest first.
  Stream<List<Import>> watchAll();

  /// Transactions on [accountId] with time in `[from, to)`, oldest first.
  Future<List<TransactionRecord>> transactionsBetween(
    int accountId, {
    required DateTime from,
    required DateTime to,
  });

  /// Sets [accountId]'s opening balance to [balanceMinor] at [at], when the
  /// account currently opens at or after [at], so a statement that reaches
  /// further back than SMS anchors the balance. Returns whether it changed.
  Future<bool> openEarlier(
    int accountId, {
    required int balanceMinor,
    required DateTime at,
  });
}

class DriftStatementImportsRepository implements StatementImportsRepository {
  DriftStatementImportsRepository(this._db);

  final AppDatabase _db;

  @override
  Future<Import?> findByHash(String fileHash) => (_db.select(
    _db.imports,
  )..where((i) => i.fileHash.equals(fileHash))).getSingleOrNull();

  @override
  Future<int> record(ImportsCompanion import) =>
      _db.into(_db.imports).insert(import);

  @override
  Stream<List<Import>> watchAll() => (_db.select(
    _db.imports,
  )..orderBy([(i) => OrderingTerm.desc(i.importedAt)])).watch();

  @override
  Future<List<TransactionRecord>> transactionsBetween(
    int accountId, {
    required DateTime from,
    required DateTime to,
  }) =>
      (_db.select(_db.transactions)
            ..where(
              (t) =>
                  t.accountId.equals(accountId) &
                  t.occurredAt.isBiggerOrEqualValue(from) &
                  t.occurredAt.isSmallerThanValue(to),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.occurredAt)]))
          .get();

  @override
  Future<bool> openEarlier(
    int accountId, {
    required int balanceMinor,
    required DateTime at,
  }) async {
    final updated =
        await (_db.update(_db.accounts)..where(
              (a) =>
                  a.id.equals(accountId) &
                  a.openingDate.isBiggerOrEqualValue(at),
            ))
            .write(
              AccountsCompanion(
                openingBalanceMinor: Value(balanceMinor),
                openingDate: Value(at),
              ),
            );
    return updated > 0;
  }
}

final statementImportsRepositoryProvider = Provider<StatementImportsRepository>(
  (ref) => DriftStatementImportsRepository(ref.watch(appDatabaseProvider)),
);
