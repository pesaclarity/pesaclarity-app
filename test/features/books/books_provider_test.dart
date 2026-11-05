import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/accounts_repository.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/ledger/balances.dart';
import 'package:pesaclarity/src/features/books/application/books_providers.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = openTestDatabase();
    addTearDown(() => BaseCurrency.code = 'KES');
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 20, 9)),
        deviceRegionProvider.overrideWithValue('KE'),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<int> add(
    int account,
    int day,
    int shillings,
    TransactionDirection direction, {
    int fee = 0,
    int? balanceAfter,
  }) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: account,
          occurredAt: eat(2026, 11, day),
          amountMinor: kes(shillings),
          feeMinor: Value(kes(fee)),
          direction: direction,
          balanceAfterMinor: Value(
            balanceAfter == null ? null : kes(balanceAfter),
          ),
          source: TransactionSource.manual,
        ),
      );

  test('the books follow the records and agree with the balances', () async {
    final mpesa = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingBalanceMinor: Value(kes(2000)),
            openingDate: eat(2026, 11, 1, 0),
          ),
        );
    await add(mpesa, 2, 1500, TransactionDirection.inflow);
    await add(mpesa, 3, 400, TransactionDirection.outflow, fee: 7);
    // M-Pesa reports more than the records explain: a balance difference.
    await add(mpesa, 4, 100, TransactionDirection.outflow, balanceAfter: 3500);

    final c = container();
    final books = await c.read(booksProvider.future);
    expect(books.unbalanced, isEmpty);
    final accounts = await c.read(accountsRepositoryProvider).openings();
    final entries = await c
        .read(transactionsRepositoryProvider)
        .ledgerEntries(from: DateTime.utc(1970), to: DateTime.utc(2027));
    final today = DateTime.utc(2026, 11, 21);
    expect(
      books.balanceOf(BookAccount.money(mpesa), currency: 'KES'),
      balanceAt(accounts.single, entries, at: today),
    );
    expect(
      books.balanceOf(BookAccount.money(mpesa), currency: 'KES'),
      kes(3500),
    );
    expect(
      books.balanceOf(BookAccount.balanceDifferences, currency: 'KES'),
      kes(3500 - (2000 + 1500 - 407 - 100)),
    );

    // A new record reaches the books.
    await add(mpesa, 10, 250, TransactionDirection.inflow);
    c.invalidate(booksProvider);
    final after = await c.read(booksProvider.future);
    expect(
      after.balanceOf(BookAccount.money(mpesa), currency: 'KES'),
      kes(3750),
    );
  });
}
