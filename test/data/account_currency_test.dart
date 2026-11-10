import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/features/sms/application/transaction_mapping.dart';

import '../helpers/test_app.dart';

/// Accounts at one bank, each in its own currency (synthetic data).
void main() {
  late AppDatabase db;
  late DriftAccountsRepository accounts;

  Future<int> equity({String currency = 'KES', String? reference}) =>
      accounts.accountForInstitution(
        'equity',
        name: 'Equity Bank',
        type: AccountType.bank,
        openingDate: DateTime.utc(2026),
        currency: currency,
        reference: reference,
      );

  Future<Account> account(int id) =>
      (db.select(db.accounts)..where((a) => a.id.equals(id))).getSingle();

  setUp(() {
    db = openTestDatabase();
    accounts = DriftAccountsRepository(db);
  });
  tearDown(() => db.close());

  test('tells accounts at one bank apart by their numbers', () async {
    final kes = await equity(reference: '0170****4321');
    final usd = await equity(currency: 'USD', reference: '0170****8765');
    expect(usd, isNot(kes));
    expect(await equity(reference: '***4321'), kes);
    expect(await equity(currency: 'USD', reference: '0170****8765'), usd);

    expect((await account(kes)).name, 'Equity Bank ···4321');
    expect((await account(usd)).name, 'Equity Bank ···8765');
    expect((await account(usd)).currency, 'USD');
    // A message without a number goes to the account in its currency.
    expect(await equity(currency: 'USD'), usd);
    expect(await equity(), kes);
  });

  test(
    'an account from before numbers takes the first one in its currency',
    () async {
      final legacy = await equity();
      expect((await account(legacy)).reference, isNull);
      final usd = await equity(currency: 'USD', reference: '0170****8765');
      expect(usd, isNot(legacy));
      expect(await equity(reference: '0170****4321'), legacy);
      expect((await account(legacy)).reference, '0170****4321');
      expect((await account(legacy)).name, 'Equity Bank ···4321');
    },
  );

  test('keeps the fuller number it sees', () async {
    final id = await equity(reference: '***4321');
    expect(await equity(reference: '0170*****4321'), id);
    expect((await account(id)).reference, '0170*****4321');
  });

  group('an account added by hand', () {
    late int cash;

    setUp(() async {
      accounts = DriftAccountsRepository(
        db,
        converter: CurrencyConverter(
          base: 'USD',
          rates: ExchangeRates.fromJson({
            'base': 'USD',
            'rates': {'SSP': 1000, 'KES': 129.2},
          }, fetchedAt: DateTime.utc(2026, 11, 3))!,
        ),
      );
      cash = await accounts.cashAccount(
        name: 'Cash',
        openingDate: DateTime.utc(2026, 11),
      );
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: cash,
              occurredAt: DateTime.utc(2026, 11, 2),
              amountMinor: 500000,
              currency: const Value('USD'),
              direction: TransactionDirection.outflow,
              source: TransactionSource.manual,
            ),
          );
    });

    test('changes currency for new amounts only', () async {
      expect(await accounts.countInOwnCurrency(cash), 1);
      expect(await accounts.setCurrency(cash, 'SSP'), isTrue);
      expect((await account(cash)).currency, 'SSP');
      final row = await db.select(db.transactions).getSingle();
      expect((row.currency, row.amountMinor), ('USD', 500000));
      expect(await accounts.countInOwnCurrency(cash), 0);
    });

    test('converts its opening balance at the rate of its date', () async {
      await accounts.setOpening(cash, 10000, DateTime.utc(2026, 11));
      expect(await accounts.setCurrency(cash, 'SSP'), isTrue);
      // USD 100.00 is SSP 100,000.00.
      expect((await account(cash)).openingBalanceMinor, 10000000);
      // No rate for XAF: nothing changes.
      expect(await accounts.setCurrency(cash, 'XAF'), isFalse);
      expect((await account(cash)).currency, 'SSP');
    });
  });

  test('amounts read in hundredths take the currency minor units', () {
    expect(inCurrencyMinor(150000, 'KES'), 150000);
    expect(inCurrencyMinor(150000, 'UGX'), 1500);
  });
}
