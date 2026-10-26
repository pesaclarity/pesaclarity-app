import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Accounts whose messages and statements feed the ledger.
abstract interface class AccountsRepository {
  Stream<List<Account>> watchAll();

  Future<int> add(AccountsCompanion account);

  /// The id of the account fed by [institutionId]'s messages, creating it
  /// with [name], [type] and [openingDate] the first time.
  Future<int> accountForInstitution(
    String institutionId, {
    required String name,
    required AccountType type,
    required DateTime openingDate,
  });
}

class DriftAccountsRepository implements AccountsRepository {
  DriftAccountsRepository(this._db);

  final AppDatabase _db;

  @override
  Stream<List<Account>> watchAll() => (_db.select(
    _db.accounts,
  )..orderBy([(a) => OrderingTerm(expression: a.name)])).watch();

  @override
  Future<int> add(AccountsCompanion account) =>
      _db.into(_db.accounts).insert(account);

  @override
  Future<int> accountForInstitution(
    String institutionId, {
    required String name,
    required AccountType type,
    required DateTime openingDate,
  }) => _db.transaction(() async {
    final existing = await (_db.select(
      _db.accounts,
    )..where((a) => a.institutionId.equals(institutionId))).getSingleOrNull();
    if (existing != null) return existing.id;
    return add(
      AccountsCompanion.insert(
        name: name,
        type: type,
        openingDate: openingDate,
        institutionId: Value(institutionId),
      ),
    );
  });
}

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => DriftAccountsRepository(ref.watch(appDatabaseProvider)),
);
