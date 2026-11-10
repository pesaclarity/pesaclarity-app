import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/features/sms/application/transaction_mapping.dart';

import '../helpers/test_app.dart';

/// An account counted in another currency keeps its numbers (synthetic data).
void main() {
  late AppDatabase db;
  late DriftAccountsRepository accounts;
  late int bank;

  Future<int> add(
    int minor, {
    String currency = 'KES',
    DateTime? at,
    int? balance,
  }) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: bank,
          occurredAt: at ?? DateTime.utc(2026, 11, 3),
          amountMinor: minor,
          currency: Value(currency),
          feeMinor: const Value(1500),
          balanceAfterMinor: Value(balance),
          fxRateCurrency: const Value('USD'),
          fxRateMicros: const Value(129000000),
          direction: TransactionDirection.inflow,
          source: TransactionSource.sms,
        ),
      );

  setUp(() async {
    db = openTestDatabase();
    accounts = DriftAccountsRepository(db);
    bank = await accounts.accountForInstitution(
      'equity',
      name: 'Equity Bank',
      type: AccountType.bank,
      openingDate: DateTime.utc(2026),
      currency: 'KES',
    );
    await accounts.setOpening(bank, 1000000, DateTime.utc(2026));
  });
  tearDown(() => db.close());

  test('a new account starts in the currency given', () async {
    expect(await accounts.currencyOf(bank), 'KES');
    final usd = await accounts.accountForInstitution(
      'other',
      name: 'Other',
      type: AccountType.bank,
      openingDate: DateTime.utc(2026),
      currency: 'USD',
    );
    expect(await accounts.currencyOf(usd), 'USD');
  });

  test('marks its transactions in the new currency, same amounts', () async {
    await add(150000, balance: 900000, at: DateTime.utc(2026, 11));
    final latest = await add(250000, at: DateTime.utc(2026, 11, 3));
    final other = await add(5000, currency: 'EUR');

    final own = await accounts.ownCurrencyTransactions(bank);
    expect(own.count, 2);
    expect(own.latest!.id, latest);

    expect(await accounts.setCurrency(bank, 'USD'), 2);
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(bank))).getSingle();
    expect(account.currency, 'USD');
    expect(account.openingBalanceMinor, 1000000);

    final rows = await (db.select(
      db.transactions,
    )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
    expect(rows.map((r) => (r.currency, r.amountMinor)), [
      ('USD', 150000),
      ('USD', 250000),
      ('EUR', 5000),
    ]);
    expect(rows.first.balanceAfterMinor, 900000);
    expect(rows.first.fxRateCurrency, isNull);
    expect(rows.first.fxRateMicros, isNull);
    // A payment in another currency keeps its rate.
    expect(rows.singleWhere((r) => r.id == other).fxRateMicros, 129000000);

    expect(await accounts.setCurrency(bank, 'USD'), 0);
  });

  test('rescales to a currency with other minor units', () async {
    await add(5000000, balance: 7500050);
    await accounts.setCurrency(bank, 'UGX');
    final row = await db.select(db.transactions).getSingle();
    // KES 50,000.00 is UGX 50,000; KES 15.00 is UGX 15; KES 75,000.50
    // rounds to UGX 75,001.
    expect(row.amountMinor, 50000);
    expect(row.feeMinor, 15);
    expect(row.balanceAfterMinor, 75001);
    final account = await db.select(db.accounts).getSingle();
    expect(account.openingBalanceMinor, 10000);
  });

  test('a message row takes its account currency', () {
    final row = TransactionsCompanion.insert(
      accountId: 1,
      occurredAt: DateTime.utc(2026, 11, 3),
      amountMinor: 150000,
      currency: const Value('KES'),
      feeMinor: const Value(1500),
      balanceAfterMinor: const Value(null),
      direction: TransactionDirection.outflow,
      source: TransactionSource.sms,
    );
    expect(inAccountCurrency(row, 'KES'), same(row));
    final usd = inAccountCurrency(row, 'USD');
    expect(usd.currency.value, 'USD');
    expect(usd.amountMinor.value, 150000);
    final ugx = inAccountCurrency(row, 'UGX');
    expect(ugx.amountMinor.value, 1500);
    expect(ugx.feeMinor.value, 15);
    expect(ugx.balanceAfterMinor.value, isNull);
  });
}
