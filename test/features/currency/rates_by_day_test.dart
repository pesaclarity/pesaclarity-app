import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/exchange_rates.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/rate_history_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/currency/data/rates_client.dart';

import '../../helpers/test_app.dart';

/// Rates whose KES rate the test sets before each fetch.
class _Rates implements RatesClient {
  _Rates(this.now);

  final DateTime Function() now;
  double kes = 130;

  @override
  Future<ExchangeRates?> fetch(String base) async => ExchangeRates.fromJson({
    'base': 'USD',
    'rates': {'KES': kes, 'EUR': 0.92},
  }, fetchedAt: now());
}

void main() {
  late AppDatabase db;
  late _Rates rates;
  var now = DateTime.utc(2026, 11, 2, 6);

  setUp(() {
    db = openTestDatabase();
    now = DateTime.utc(2026, 11, 2, 6);
    rates = _Rates(() => now);
    addTearDown(() => BaseCurrency.code = 'KES');
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ratesClientProvider.overrideWithValue(rates),
        clockProvider.overrideWithValue(() => now),
        deviceRegionProvider.overrideWithValue('SS'),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<int> mpesa() => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          currency: const Value('KES'),
          openingDate: DateTime.utc(2026),
        ),
      );

  Future<int> pay(int accountId, int minor, DateTime at) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: accountId,
          occurredAt: at,
          amountMinor: minor,
          currency: const Value('KES'),
          direction: TransactionDirection.outflow,
          source: TransactionSource.manual,
        ),
      );

  Future<Map<int, int>> inBase(ProviderContainer c) async => {
    for (final e
        in await c
            .read(transactionsRepositoryProvider)
            .ledgerEntries(from: DateTime.utc(2026), to: DateTime.utc(2027)))
      e.id: e.amountMinor,
  };

  test('each payment converts at the rates of its day, which stay', () async {
    final c = container();
    final controller = c.read(currencyControllerProvider.notifier);
    await c.read(currencyControllerProvider.future);
    await controller.choose('USD');
    final account = await mpesa();

    // 2 Nov: 130 KES per USD.
    await controller.refreshRates(force: true);
    final rent = await pay(account, 2600000, DateTime.utc(2026, 11, 2, 9));
    // A later fetch the same day changes nothing for that day.
    rates.kes = 131;
    now = DateTime.utc(2026, 11, 2, 20);
    await controller.refreshRates(force: true);
    // 4 Nov: 128.
    rates.kes = 128;
    now = DateTime.utc(2026, 11, 4, 6);
    await controller.refreshRates(force: true);
    final shop = await pay(account, 256000, DateTime.utc(2026, 11, 4, 9));

    final amounts = await inBase(c);
    expect(amounts[rent], 20000); // USD 200.00 at 130
    expect(amounts[shop], 2000); // USD 20.00 at 128

    final history = await c.read(rateHistoryRepositoryProvider).read();
    expect(
      [for (final d in history.days) d.day],
      [CalendarDate(2026, 11, 2), CalendarDate(2026, 11, 4)],
    );
  });

  test('the rate the person got wins, and can be cleared', () async {
    final c = container();
    final controller = c.read(currencyControllerProvider.notifier);
    await c.read(currencyControllerProvider.future);
    await controller.choose('USD');
    await controller.refreshRates(force: true);
    final id = await pay(await mpesa(), 2580000, DateTime.utc(2026, 11, 2, 9));
    final repo = c.read(transactionsRepositoryProvider);

    await repo.setRateGot(id, currency: 'USD', rate: 129);
    expect((await inBase(c))[id], 20000);
    final saved = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(id))).getSingle();
    expect((saved.fxRateCurrency, saved.fxRateMicros), ('USD', 129000000));

    await repo.setRateGot(id, currency: 'USD');
    // Back to the day's 130.
    expect((await inBase(c))[id], 19846);
  });

  test('rates saved before keeping them by day become their day', () async {
    await DriftAppSettingsRepository(db).writeJson(
      CurrencyController.ratesKey,
      ExchangeRates.fromJson({
        'base': 'USD',
        'rates': {'KES': 129.2},
      }, fetchedAt: DateTime.utc(2026, 10, 27, 6))!.toJson(),
    );
    final c = container();
    final settings = await c.read(currencyControllerProvider.future);
    expect(
      [for (final d in settings.history!.days) d.day],
      [CalendarDate(2026, 10, 27)],
    );
  });

  test('a new cash account is in the base currency', () async {
    final c = container();
    await c.read(currencyControllerProvider.future);
    await c.read(currencyControllerProvider.notifier).choose('USD');
    final id = await c
        .read(accountsRepositoryProvider)
        .cashAccount(name: 'Cash', openingDate: DateTime.utc(2026, 11));
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(id))).getSingle();
    expect(account.currency, 'USD');
  });
}
