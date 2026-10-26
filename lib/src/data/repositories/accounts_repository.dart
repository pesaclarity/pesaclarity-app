import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Accounts whose messages and statements feed the ledger.
abstract interface class AccountsRepository {
  Stream<List<Account>> watchAll();

  Future<int> add(AccountsCompanion account);
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
}

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => DriftAccountsRepository(ref.watch(appDatabaseProvider)),
);
