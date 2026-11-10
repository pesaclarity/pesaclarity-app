import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/exchange_rates.dart';
import '../../core/money/money.dart';
import '../../domain/ledger/balances.dart';
import '../../features/currency/application/currency_controller.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Accounts whose messages and statements feed the ledger.
abstract interface class AccountsRepository {
  Stream<List<Account>> watchAll();

  Future<int> add(AccountsCompanion account);

  /// The account fed by [institutionId]'s messages, made the first time in
  /// [currency], the currency those messages usually use.
  Future<int> accountForInstitution(
    String institutionId, {
    required String name,
    required AccountType type,
    required DateTime openingDate,
    String? currency,
  });

  /// The currency [accountId] counts in.
  Future<String> currencyOf(int accountId);

  /// How many of [accountId]'s transactions are in its own currency, and the
  /// latest of them: what [setCurrency] would mark in a new one.
  Future<({int count, TransactionRecord? latest})> ownCurrencyTransactions(
    int accountId,
  );

  /// Counts [accountId] in [currency] from now on, and marks its
  /// transactions in its old currency as [currency] with the same amounts,
  /// since they were in [currency] all along. Returns how many it marked.
  Future<int> setCurrency(int accountId, String currency);

  /// Every account's opening balance, for working out balances.
  Future<List<AccountOpening>> openings();

  /// Starts [accountId]'s records at [date] with [balanceMinor], in the
  /// account's own currency.
  Future<void> setOpening(int accountId, int balanceMinor, DateTime date);

  /// The id of the cash account (the drawer), creating it the first time.
  Future<int> cashAccount({
    required String name,
    required DateTime openingDate,
  });
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
    String? currency,
  }) => _db.transaction(() async {
    final existing = await (_db.select(
      _db.accounts,
    )..where((a) => a.institutionId.equals(institutionId))).getSingleOrNull();
    if (existing != null) return existing.id;
    return add(
      AccountsCompanion.insert(
        name: name,
        type: type,
        currency: Value.absentIfNull(currency),
        openingDate: openingDate,
        institutionId: Value(institutionId),
      ),
    );
  });

  @override
  Future<String> currencyOf(int accountId) async {
    final query = _db.selectOnly(_db.accounts)
      ..addColumns([_db.accounts.currency])
      ..where(_db.accounts.id.equals(accountId));
    return (await query.getSingle()).read(_db.accounts.currency)!;
  }

  @override
  Future<({int count, TransactionRecord? latest})> ownCurrencyTransactions(
    int accountId,
  ) async {
    final currency = await currencyOf(accountId);
    final t = _db.transactions;
    final rows =
        await (_db.select(t)
              ..where(
                (r) =>
                    r.accountId.equals(accountId) & r.currency.equals(currency),
              )
              ..orderBy([(r) => OrderingTerm.desc(r.occurredAt)]))
            .get();
    return (count: rows.length, latest: rows.firstOrNull);
  }

  @override
  Future<int> setCurrency(int accountId, String currency) =>
      _db.transaction(() async {
        final account = await (_db.select(
          _db.accounts,
        )..where((a) => a.id.equals(accountId))).getSingle();
        final from = account.currency;
        if (from == currency) return 0;
        // Same amounts, in the new currency's minor units: KES 50,000.00 is
        // UGX 50,000.
        int scale(int minor) => rescaleMinor(
          minor,
          fromDigits: minorUnitDigits(from),
          toDigits: minorUnitDigits(currency),
        );
        await (_db.update(
          _db.accounts,
        )..where((a) => a.id.equals(accountId))).write(
          AccountsCompanion(
            currency: Value(currency),
            openingBalanceMinor: Value(scale(account.openingBalanceMinor)),
          ),
        );
        final t = _db.transactions;
        final rows =
            await (_db.select(t)..where(
                  (r) =>
                      r.accountId.equals(accountId) & r.currency.equals(from),
                ))
                .get();
        for (final row in rows) {
          await (_db.update(t)..where((r) => r.id.equals(row.id))).write(
            TransactionsCompanion(
              currency: Value(currency),
              amountMinor: Value(scale(row.amountMinor)),
              feeMinor: Value(scale(row.feeMinor)),
              balanceAfterMinor: Value(
                row.balanceAfterMinor == null
                    ? null
                    : scale(row.balanceAfterMinor!),
              ),
              // A rate got between the old currency and another no longer
              // describes it.
              fxRateCurrency: const Value(null),
              fxRateMicros: const Value(null),
            ),
          );
        }
        return rows.length;
      });

  @override
  Future<void> setOpening(int accountId, int balanceMinor, DateTime date) =>
      (_db.update(_db.accounts)..where((a) => a.id.equals(accountId))).write(
        AccountsCompanion(
          openingBalanceMinor: Value(balanceMinor),
          openingDate: Value(date),
        ),
      );

  @override
  Future<int> cashAccount({
    required String name,
    required DateTime openingDate,
  }) => _db.transaction(() async {
    final existing =
        await (_db.select(_db.accounts)
              ..where((a) => a.type.equalsValue(AccountType.cash))
              ..orderBy([(a) => OrderingTerm(expression: a.id)]))
            .get();
    if (existing.isNotEmpty) return existing.first.id;
    return add(
      AccountsCompanion.insert(
        name: name,
        type: AccountType.cash,
        // Cash in hand counts in the base currency.
        currency: Value(_converter?.base ?? BaseCurrency.code),
        openingDate: openingDate,
      ),
    );
  });

  @override
  Future<List<AccountOpening>> openings() async => [
    for (final a in await _db.select(_db.accounts).get())
      // At the rates of the day the account opened.
      if (_converter
              ?.convert(a.openingBalanceMinor, a.currency, a.openingDate)
              ?.baseMinor
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
