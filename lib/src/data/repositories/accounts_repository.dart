import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/ledger/balances.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Accounts whose messages and statements feed the ledger.
abstract interface class AccountsRepository {
  Stream<List<Account>> watchAll();

  Future<int> add(AccountsCompanion account);

  /// Every account's opening balance, for working out balances.
  Future<List<AccountOpening>> openings();
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
  Future<List<AccountOpening>> openings() async => [
    for (final a in await _db.select(_db.accounts).get())
      AccountOpening(
        id: a.id,
        type: a.type,
        openingBalanceMinor: a.openingBalanceMinor,
        openingDate: a.openingDate,
        currency: a.currency,
      ),
  ];
}

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => DriftAccountsRepository(ref.watch(appDatabaseProvider)),
);
