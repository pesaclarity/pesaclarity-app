// Many-currency screens and the personal Activity screen for the marketing
// screenshots, with made-up records (README, Screenshots).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
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
import 'package:pesaclarity/src/domain/ledger/own_transfers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/accounts/presentation/my_accounts_settings_screen.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/currency/data/rates_client.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/features/sms/application/message_recheck.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

final _now = eat(2026, 11, 12, 9, 30);

/// Shorter category names, as someone may rename them.
Future<void> _rename(AppDatabase db) async {
  for (final (key, name) in [
    ('groceries', 'Food'),
    ('rent', 'Rent'),
    ('utilities', 'Utilities'),
  ]) {
    await (db.update(db.categories)..where((c) => c.key.equals(key))).write(
      CategoriesCompanion(name: Value(name)),
    );
  }
}

Future<int> _category(AppDatabase db, String key) async => (await (db.select(
  db.categories,
)..where((c) => c.key.equals(key))).getSingle()).id;

Future<int> _tx(
  AppDatabase db, {
  required int account,
  required DateTime at,
  required int minor,
  required String currency,
  required bool inflow,
  String? name,
  String? value,
  int? category,
}) => db
    .into(db.transactions)
    .insert(
      TransactionsCompanion.insert(
        accountId: account,
        occurredAt: at,
        amountMinor: minor,
        currency: Value(currency),
        direction: inflow
            ? TransactionDirection.inflow
            : TransactionDirection.outflow,
        kind: Value(inflow ? TransactionKind.received : TransactionKind.sent),
        source: TransactionSource.sms,
        counterpartyName: Value(name),
        counterpartyKind: Value(
          value == null ? null : PayeeIdentifierKind.phone,
        ),
        counterpartyValue: Value(value),
        categoryOverrideId: Value(category),
      ),
    );

/// A person who counts in USD, with KES, USD and SSP accounts.
class _Dollars {
  _Dollars(this.db);

  final AppDatabase db;
  late int mpesa;
  late int equityKes;
  late int equityUsd;
  late int cash;

  Future<void> seed() async {
    final settings = DriftAppSettingsRepository(db);
    await settings.writeJson(CurrencyController.settingsKey, {
      'base': 'USD',
      'chosen': true,
      'ownRates': <String, Object?>{},
    });
    final rates = ExchangeRates.fromJson({
      'base': 'USD',
      'rates': {'KES': 129.2, 'SSP': 1000},
    }, fetchedAt: DateTime.utc(2026, 11, 12, 6))!;
    await settings.writeJson(CurrencyController.ratesKey, rates.toJson());
    final history = DriftRateHistoryRepository(db);
    for (final d in [1, 5, 10, 11, 12]) {
      await history.keep(CalendarDate(2026, 11, d), rates);
    }
    final accounts = DriftAccountsRepository(db);
    final opening = DateTime.utc(2026);
    mpesa = await accounts.accountForInstitution(
      'mpesa',
      name: 'M-Pesa',
      type: AccountType.mpesa,
      openingDate: opening,
      currency: 'KES',
    );
    equityKes = await accounts.accountForInstitution(
      'equity',
      name: 'Equity Bank',
      type: AccountType.bank,
      openingDate: opening,
      currency: 'KES',
      reference: '0170*****4321',
    );
    equityUsd = await accounts.accountForInstitution(
      'equity',
      name: 'Equity Bank',
      type: AccountType.bank,
      openingDate: opening,
      currency: 'USD',
      reference: '0170*****8765',
    );
    cash = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Cash',
            type: AccountType.cash,
            currency: const Value('SSP'),
            openingDate: opening,
          ),
        );
  }

  Future<void> activity() async {
    await _tx(
      db,
      account: equityUsd,
      at: eat(2026, 11, 12, 7, 42),
      minor: 250000,
      currency: 'USD',
      inflow: true,
      name: 'Lakeview Consulting',
      category: await _category(db, 'salary'),
    );
    await _tx(
      db,
      account: mpesa,
      at: eat(2026, 11, 12, 8, 15),
      minor: 2500000,
      currency: 'KES',
      inflow: false,
      name: 'Achieng Otieno',
      category: await _category(db, 'rent'),
    );
    await _tx(
      db,
      account: equityKes,
      at: eat(2026, 11, 11, 18, 5),
      minor: 299900,
      currency: 'KES',
      inflow: false,
      name: 'Home internet',
      category: await _category(db, 'utilities'),
    );
    await _tx(
      db,
      account: mpesa,
      at: eat(2026, 11, 11, 13, 20),
      minor: 144000,
      currency: 'KES',
      inflow: false,
      name: 'Green Basket Grocers',
      category: await _category(db, 'groceries'),
    );
    await _tx(
      db,
      account: cash,
      at: eat(2026, 11, 10, 17),
      minor: 1500000,
      currency: 'SSP',
      inflow: false,
      name: 'Market',
      category: await _category(db, 'groceries'),
    );
    await DriftAppSettingsRepository(db).writeJson(
      MessageRecheck.noticeKey,
      RecheckNotice(
        count: 23,
        accountId: equityUsd,
        currency: 'USD',
        currencyChanged: true,
      ).toJson(),
    );
  }
}

/// [home] in the personal tab bar; over [root] when given.
Widget _app(AppDatabase db, Widget home, {required int tab, Widget? root}) =>
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        ratesConfiguredProvider.overrideWithValue(true),
        deviceRegionProvider.overrideWithValue('KE'),
        clockProvider.overrideWithValue(() => _now),
        activeSpaceProvider.overrideWithValue(Space.personal),
        ...appLockOverrides(),
      ],
      child: shotApp(
        tabShell(home, tabs: personalTabs, index: tab, root: root),
      ),
    );

void main() {
  tearDown(() => BaseCurrency.code = 'KES');

  screenshot('accounts', (tester) async {
    final db = openTestDatabase();
    final p = _Dollars(db);
    await tester.runAsync(p.seed);
    await tester.pumpWidget(
      _app(
        db,
        const MyAccountsSettingsScreen(),
        tab: 0,
        root: const HomeScreen(),
      ),
    );
    await settleFrames(tester);
    await tester.pumpAndSettle();
    await snap(tester);
  });

  screenshot('currencies', (tester) async {
    final db = openTestDatabase();
    final p = _Dollars(db);
    await tester.runAsync(() async {
      await _rename(db);
      await p.seed();
      await p.activity();
    });
    await tester.pumpWidget(_app(db, const ActivityScreen(), tab: 1));
    await settleFrames(tester);
    await snap(tester);
  });

  // The personal Activity screen, with the content of the site's old one
  // and a placeholder number for the unnamed payee.
  screenshot('activity', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() async {
      await _rename(db);
      final accounts = DriftAccountsRepository(db);
      final opening = DateTime.utc(2026);
      final mpesa = await accounts.accountForInstitution(
        'mpesa',
        name: 'M-Pesa',
        type: AccountType.mpesa,
        openingDate: opening,
        currency: 'KES',
      );
      final im = await accounts.accountForInstitution(
        'im_bank',
        name: 'I&M',
        type: AccountType.bank,
        openingDate: opening,
        currency: 'KES',
      );
      Future<int> spend(
        DateTime at,
        int shillings,
        String? name,
        String? key, {
        String? value,
      }) async => _tx(
        db,
        account: mpesa,
        at: at,
        minor: kes(shillings),
        currency: 'KES',
        inflow: false,
        name: name,
        value: value,
        category: key == null ? null : await _category(db, key),
      );
      await spend(
        eat(2026, 11, 12, 8, 40),
        1440,
        'Green Basket Grocers',
        'groceries',
      );
      await spend(eat(2026, 11, 12, 7, 55), 300, 'Sunrise Cafe', 'eating_out');
      final out = await _tx(
        db,
        account: im,
        at: eat(2026, 11, 12, 7, 10),
        minor: kes(2000),
        currency: 'KES',
        inflow: false,
        name: 'M-Pesa',
      );
      final inn = await _tx(
        db,
        account: mpesa,
        at: eat(2026, 11, 12, 7, 11),
        minor: kes(2000),
        currency: 'KES',
        inflow: true,
        name: 'I&M Bank',
      );
      await DriftTransactionsRepository(db)
          .saveTransferPairs([TransferPair(out, inn)]);
      await spend(eat(2026, 11, 11, 19, 5), 500, 'KPLC tokens', 'utilities');
      await spend(
        eat(2026, 11, 11, 12, 30),
        350,
        null,
        null,
        value: '0700***000',
      );
      // Earlier in the week, so the week's totals match the old screen.
      await spend(eat(2026, 11, 11, 8, 15), 250, 'Sunrise Cafe', 'eating_out');
      await spend(eat(2026, 11, 10, 18), 980, 'Corner Pharmacy', 'health');
      await spend(eat(2026, 11, 9, 17, 30), 4000, 'School shoes', 'shopping');
      await _tx(
        db,
        account: mpesa,
        at: eat(2026, 11, 10, 10),
        minor: kes(2500),
        currency: 'KES',
        inflow: true,
        name: 'Peter Kamau',
        category: await _category(db, 'money_received'),
      );
    });
    await tester.pumpWidget(_app(db, const ActivityScreen(), tab: 1));
    await settleFrames(tester);
    await snap(tester);
  });
}
