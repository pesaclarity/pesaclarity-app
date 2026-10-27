import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/exchange_rates.dart';
import '../../domain/ledger/balances.dart';
import '../../features/currency/application/currency_controller.dart';
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

  /// Every account's opening balance, for working out balances.
  Future<List<AccountOpening>> openings();
}

class DriftAccountsRepository implements AccountsRepository {
  DriftAccountsRepository(this._db, {this._converter});

  final AppDatabase _db;

  /// Converts opening balances into the base currency; none leaves them as
  /// stored.
  final CurrencyConverter? _converter;

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

  @override
  Future<List<AccountOpening>> openings() async => [
    for (final a in await _db.select(_db.accounts).get())
      if (_converter?.toBase(a.openingBalanceMinor, a.currency)
          case final inBase? when a.currency != _converter!.base)
        AccountOpening(
          id: a.id,
          type: a.type,
          openingBalanceMinor: inBase,
          openingDate: a.openingDate,
          currency: _converter.base,
        )
      else
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
  (ref) => DriftAccountsRepository(
    ref.watch(appDatabaseProvider),
    converter: ref.watch(currencyConverterProvider),
  ),
);
