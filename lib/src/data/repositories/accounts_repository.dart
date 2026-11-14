import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/exchange_rates.dart';
import '../../core/money/money.dart';
import '../../domain/accounts/account_reference.dart';
import '../../domain/ledger/balances.dart';
import '../../features/currency/application/currency_controller.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Accounts whose messages and statements feed the ledger.
abstract interface class AccountsRepository {
  Stream<List<Account>> watchAll();

  /// Every account, by name, once.
  Future<List<Account>> all();

  Future<int> add(AccountsCompanion account);

  /// The account a message from [institutionId] belongs to. [reference]
  /// is the account number the message prints (often masked) and
  /// [currency] the currency of its amount: accounts at one institution are
  /// told apart by the digits their numbers show, then by currency. A new
  /// account is made with [name], [type], [openingDate] and [currency] when
  /// none matches; accounts that share an institution get the last digits
  /// of their number in their name.
  Future<int> accountForInstitution(
    String institutionId, {
    required String name,
    required AccountType type,
    required DateTime openingDate,
    required String currency,
    String? reference,
  });

  /// The currency [accountId] counts in.
  Future<String> currencyOf(int accountId);

  /// How many of [accountId]'s transactions are in its own currency.
  Future<int> countInOwnCurrency(int accountId);

  /// Counts [accountId], an account added by hand, in [currency] from now
  /// on. Its transactions keep their currencies; its opening balance
  /// converts at the rate of its date. False, changing nothing, when that
  /// rate is missing.
  Future<bool> setCurrency(int accountId, String currency);

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
  Future<List<Account>> all() => (_db.select(
    _db.accounts,
  )..orderBy([(a) => OrderingTerm(expression: a.name)])).get();

  @override
  Future<int> add(AccountsCompanion account) =>
      _db.into(_db.accounts).insert(account);

  @override
  Future<int> accountForInstitution(
    String institutionId, {
    required String name,
    required AccountType type,
    required DateTime openingDate,
    required String currency,
    String? reference,
  }) => _db.transaction(() async {
    final existing =
        await (_db.select(_db.accounts)
              ..where((a) => a.institutionId.equals(institutionId))
              ..orderBy([(a) => OrderingTerm(expression: a.id)]))
            .get();
    final printed = AccountReference.tryParse(reference);
    Account? pick(Iterable<Account> accounts) =>
        accounts.where((a) => a.currency == currency).firstOrNull;

    if (printed == null) {
      final match = pick(existing) ?? existing.firstOrNull;
      if (match != null) return match.id;
    } else {
      final numbered = existing.where((a) {
        final known = AccountReference.tryParse(a.reference);
        return known != null && known.sameAs(printed);
      });
      final match =
          pick(numbered) ??
          numbered.firstOrNull ??
          pick(existing.where((a) => a.reference == null));
      if (match != null) {
        final known = AccountReference.tryParse(match.reference);
        if (known == null || known.showsLessThan(printed)) {
          await (_db.update(_db.accounts)..where((a) => a.id.equals(match.id)))
              .write(AccountsCompanion(reference: Value(reference)));
          if (existing.length > 1 && known == null) {
            await _nameApart(match.copyWith(reference: Value(reference)), name);
          }
        }
        return match.id;
      }
    }

    final id = await add(
      AccountsCompanion.insert(
        name: existing.isEmpty || printed == null
            ? name
            : '$name ···${printed.lastDigits}',
        type: type,
        currency: Value(currency),
        openingDate: openingDate,
        institutionId: Value(institutionId),
        reference: Value(reference),
      ),
    );
    // The first account now shares its institution: name it apart too.
    for (final other in existing) {
      await _nameApart(other, name);
    }
    return id;
  });

  /// Adds the last digits of [account]'s number to its name while it still
  /// has the institution's [name].
  Future<void> _nameApart(Account account, String name) async {
    final digits = AccountReference.tryParse(account.reference)?.lastDigits;
    if (digits == null || account.name != name) return;
    await (_db.update(_db.accounts)..where((a) => a.id.equals(account.id)))
        .write(AccountsCompanion(name: Value('$name ···$digits')));
  }

  @override
  Future<String> currencyOf(int accountId) async {
    final query = _db.selectOnly(_db.accounts)
      ..addColumns([_db.accounts.currency])
      ..where(_db.accounts.id.equals(accountId));
    return (await query.getSingle()).read(_db.accounts.currency)!;
  }

  @override
  Future<int> countInOwnCurrency(int accountId) async {
    final currency = await currencyOf(accountId);
    final t = _db.transactions;
    final count = t.id.count();
    final query = _db.selectOnly(t)
      ..addColumns([count])
      ..where(t.accountId.equals(accountId) & t.currency.equals(currency));
    return (await query.getSingle()).read(count) ?? 0;
  }

  @override
  Future<bool> setCurrency(int accountId, String currency) =>
      _db.transaction(() async {
        final account = await (_db.select(
          _db.accounts,
        )..where((a) => a.id.equals(accountId))).getSingle();
        if (account.currency == currency) return true;
        final opening = _openingIn(account, currency);
        if (opening == null) return false;
        await (_db.update(
          _db.accounts,
        )..where((a) => a.id.equals(accountId))).write(
          AccountsCompanion(
            currency: Value(currency),
            openingBalanceMinor: Value(opening),
          ),
        );
        return true;
      });

  /// [account]'s opening balance in [currency], at the rate of its date.
  int? _openingIn(Account account, String currency) {
    final minor = account.openingBalanceMinor;
    if (minor == 0) return 0;
    final converter = _converter;
    final inBase = converter?.convert(
      minor,
      account.currency,
      account.openingDate,
    );
    if (converter == null || inBase == null) return null;
    final step = converter.rateOn(currency, account.openingDate);
    if (step == null) return null;
    return convertMinor(
      inBase.baseMinor,
      from: converter.base,
      to: currency,
      rate: step.rate,
    );
  }

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
