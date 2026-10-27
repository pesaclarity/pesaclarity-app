import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/currency/data/rates_client.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

class _FakeRates implements RatesClient {
  final asked = <String>[];
  bool fail = false;

  @override
  Future<ExchangeRates?> fetch(String base) async {
    asked.add(base);
    if (fail) throw Exception('offline');
    return ExchangeRates.fromJson({
      'base': 'USD',
      'rates': {'KES': 129.2, 'EUR': 0.92},
    }, fetchedAt: DateTime.utc(2026, 10, 27, 6));
  }
}

void main() {
  late AppDatabase db;
  late _FakeRates rates;
  var now = DateTime.utc(2026, 10, 27, 9);

  setUp(() {
    db = openTestDatabase();
    rates = _FakeRates();
    now = DateTime.utc(2026, 10, 27, 9);
    addTearDown(() => BaseCurrency.code = 'KES');
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ratesClientProvider.overrideWithValue(rates),
        clockProvider.overrideWithValue(() => now),
        deviceRegionProvider.overrideWithValue('KE'),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<int> account(String currency) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'Account $currency',
          type: AccountType.bank,
          currency: Value(currency),
          openingDate: DateTime.utc(2026),
        ),
      );

  Future<void> spend(int accountId, int minor, String currency) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: accountId,
          occurredAt: eat(2026, 10, 20),
          amountMinor: minor,
          currency: Value(currency),
          feeMinor: const Value(100),
          direction: TransactionDirection.outflow,
          source: TransactionSource.manual,
        ),
      );

  test('KES until the person chooses, and the choice sets the base', () async {
    final c = container();
    expect((await c.read(currencyControllerProvider.future)).base, 'KES');
    await c.read(currencyControllerProvider.notifier).choose('EUR');
    expect(c.read(baseCurrencyProvider), 'EUR');
    expect(BaseCurrency.code, 'EUR');
    expect(Money(1).currency, 'EUR');
  });

  test('fetches rates when stale, and keeps the last ones offline', () async {
    final c = container();
    final controller = c.read(currencyControllerProvider.notifier);
    await c.read(currencyControllerProvider.future);
    expect(await controller.refreshRates(), isTrue);
    expect(rates.asked, ['KES']);
    // Fresh for 12 hours.
    expect(await controller.refreshRates(), isTrue);
    expect(rates.asked, hasLength(1));

    now = now.add(const Duration(hours: 13));
    rates.fail = true;
    expect(await controller.refreshRates(), isFalse);
    expect(c.read(currencyControllerProvider).value!.rates, isNotNull);
  });

  test('reads transactions in another currency in the base, keeping the '
      'original', () async {
    final c = container();
    final kes = await account('KES');
    final usd = await account('USD');
    await spend(kes, 50000, 'KES');
    await spend(usd, 699, 'USD');
    await c.read(currencyControllerProvider.future);
    await c.read(currencyControllerProvider.notifier).refreshRates();

    final entries = await c
        .read(transactionsRepositoryProvider)
        .ledgerEntries(from: DateTime.utc(2026), to: DateTime.utc(2027));
    final converted = entries.firstWhere((e) => e.originalCurrency == 'USD');
    expect(converted.currency, 'KES');
    expect(converted.amountMinor, 90311);
    expect(converted.originalAmountMinor, 699);
    // USD 1.00 fee is KES 129.20.
    expect(converted.feeMinor, 12920);
    final native = entries.firstWhere((e) => e.originalCurrency == null);
    expect((native.currency, native.amountMinor), ('KES', 50000));
  });

  test('without a rate, an entry keeps its own currency', () async {
    final c = container();
    await spend(await account('USD'), 699, 'USD');
    await c.read(currencyControllerProvider.future);
    final entry =
        (await c
                .read(transactionsRepositoryProvider)
                .ledgerEntries(
                  from: DateTime.utc(2026),
                  to: DateTime.utc(2027),
                ))
            .single;
    expect((entry.currency, entry.amountMinor), ('USD', 699));
  });

  test('switching converts what was typed in the old base, not the '
      'ledger', () async {
    final c = container();
    final kes = await account('KES');
    await spend(kes, 1292000, 'KES');
    await db
        .into(db.goals)
        .insert(GoalsCompanion.insert(name: 'Laptop', targetMinor: 12920000));
    await db
        .into(db.recurring)
        .insert(
          RecurringCompanion.insert(
            name: 'Rent',
            amountMinor: 1292000,
            frequency: RecurrenceFrequency.monthly,
            startDate: DateTime.utc(2026),
          ),
        );
    await db
        .into(db.debts)
        .insert(
          DebtsCompanion.insert(
            lender: 'Bank',
            type: DebtType.bankLoan,
            startingBalanceMinor: 258400,
          ),
        );
    final controller = c.read(currencyControllerProvider.notifier);
    await c.read(currencyControllerProvider.future);

    // No rate yet: nothing changes.
    expect(await controller.switchTo('USD'), isFalse);
    expect(c.read(baseCurrencyProvider), 'KES');

    await controller.refreshRates();
    expect(await controller.switchTo('USD'), isTrue);
    expect(c.read(baseCurrencyProvider), 'USD');

    final goal = await db.select(db.goals).getSingle();
    expect((goal.targetMinor, goal.currency), (100000, 'USD'));
    expect((await db.select(db.recurring).getSingle()).amountMinor, 10000);
    final debt = await db.select(db.debts).getSingle();
    expect((debt.startingBalanceMinor, debt.currency), (2000, 'USD'));
    // The transaction keeps its shillings; it is read in dollars.
    final row = await db.select(db.transactions).getSingle();
    expect((row.amountMinor, row.currency), (1292000, 'KES'));
    final entry =
        (await c
                .read(transactionsRepositoryProvider)
                .ledgerEntries(
                  from: DateTime.utc(2026),
                  to: DateTime.utc(2027),
                ))
            .single;
    expect((entry.currency, entry.amountMinor), ('USD', 10000));
  });

  test('own rates win, and move with the base', () async {
    final c = container();
    final controller = c.read(currencyControllerProvider.notifier);
    await c.read(currencyControllerProvider.future);
    await controller.refreshRates();
    await controller.setOwnRate('USD', 0.01);
    expect(c.read(currencyConverterProvider).rateFor('USD'), 0.01);
    await controller.setOwnRate('USD', null);
    expect(
      c.read(currencyConverterProvider).rateFor('USD'),
      closeTo(1 / 129.2, 1e-9),
    );
  });

  test('builds a rates address only for https templates', () {
    expect(
      ratesUrl('https://rates.example.org/latest/{base}', 'KES').toString(),
      'https://rates.example.org/latest/KES',
    );
    expect(ratesUrl('http://rates.example.org/{base}', 'KES'), isNull);
    expect(ratesUrl('https://rates.example.org/latest', 'KES'), isNull);
    expect(ratesUrl('', 'KES'), isNull);
  });
}
