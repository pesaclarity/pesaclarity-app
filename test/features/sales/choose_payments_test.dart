import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/sales/sale_matching.dart';
import 'package:pesaclarity/src/domain/spaces/space_categories.dart';
import 'package:pesaclarity/src/features/books/application/books_providers.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/sales/presentation/choose_payments_sheet.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late int mpesa;
  final now = eat(2026, 11, 5, 14, 40);

  setUp(() async {
    db = openTestDatabase();
    mpesa = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: eat(2026, 11, 1, 0),
          ),
        );
  });

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => now),
  ];

  ProviderContainer container() {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    return c;
  }

  Future<int> message(
    int amount, {
    int minutes = 1,
    TransactionDirection direction = TransactionDirection.inflow,
    String name = 'Grace W.',
  }) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: mpesa,
          occurredAt: now.add(Duration(minutes: minutes)),
          amountMinor: amount,
          direction: direction,
          kind: Value(
            direction == TransactionDirection.inflow
                ? TransactionKind.received
                : TransactionKind.sent,
          ),
          source: TransactionSource.sms,
          counterpartyName: Value(name),
        ),
      );

  /// Sells [amount] by M-Pesa with nothing to match yet, and returns the
  /// waiting part.
  Future<WaitingPayment> sell(ProviderContainer c, int amount) async {
    final outcome = await c.read(salesControllerProvider).sell([
      SalePart(SalePaymentMethod.mpesa, amount),
    ]);
    return outcome.waiting.single;
  }

  Future<int> salesInBooks(ProviderContainer c) async {
    final books = await c.read(booksProvider.future);
    expect(books.unbalanced, isEmpty);
    final sales = (await (db.select(
      db.categories,
    )..where((c) => c.key.equals(salesCategoryKey))).getSingle()).id;
    return books.balanceOf(
      BookAccount.category(sales, income: true),
      currency: 'KES',
    );
  }

  test('two payments that add up pay one sale', () async {
    final c = container();
    final w = await sell(c, 18000);
    await message(10000);
    await message(8000, minutes: 2);
    final controller = c.read(salesControllerProvider);
    final candidates = await controller.candidatesFor(w);
    expect(candidates, hasLength(2));
    await controller.settle(w, candidates);
    expect(await controller.waiting(), isEmpty);
    expect(await salesInBooks(c), 18000);
  });

  test('paid less: they owe the rest', () async {
    final c = container();
    final w = await sell(c, 50000);
    await message(45000);
    final controller = c.read(salesControllerProvider);
    await controller.settle(
      w,
      await controller.candidatesFor(w),
      short: ShortBy.theyOweIt,
      credit: const CreditTerms(customer: 'Otieno'),
    );
    final loan = (await db.select(db.lentLoans).get()).single;
    expect(loan.person, 'Otieno');
    expect(loan.amountMinor, 5000);
    expect(await salesInBooks(c), 50000);
  });

  test('paid less: a discount makes the sale smaller', () async {
    final c = container();
    final w = await sell(c, 50000);
    await message(45000);
    final controller = c.read(salesControllerProvider);
    await controller.settle(
      w,
      await controller.candidatesFor(w),
      short: ShortBy.discount,
    );
    expect((await db.select(db.sales).get()).single.totalMinor, 45000);
    expect(await salesInBooks(c), 45000);
    expect(await controller.waiting(), isEmpty);
  });

  test('paid less: the rest in cash, or another payment to come', () async {
    final c = container();
    final controller = c.read(salesControllerProvider);
    final first = await sell(c, 50000);
    await message(45000);
    await controller.settle(
      first,
      await controller.candidatesFor(first),
      short: ShortBy.restInCash,
    );
    expect(await salesInBooks(c), 50000);

    final second = await sell(c, 30000);
    await message(20000, minutes: 5, name: 'Peter K.');
    await controller.settle(second, [
      for (final e in await controller.candidatesFor(second))
        if (e.amountMinor == 20000) e,
    ], short: ShortBy.anotherPayment);
    final left = await controller.waiting();
    expect(left.single.amountMinor, 10000);
  });

  test('paid more: change in cash leaves the sale as it was', () async {
    final c = container();
    final w = await sell(c, 18000);
    await message(20000);
    final controller = c.read(salesControllerProvider);
    await controller.settle(
      w,
      await controller.candidatesFor(w),
      over: OverBy.changeInCash,
    );
    final change =
        (await (db.select(db.transactions)..where(
                  (t) => t.direction.equalsValue(TransactionDirection.outflow),
                ))
                .get())
            .single;
    expect(change.amountMinor, 2000);
    expect(change.kind, TransactionKind.reversal);
    expect(await salesInBooks(c), 18000);
  });

  test('paid more: change by M-Pesa waits for its message', () async {
    final c = container();
    final w = await sell(c, 18000);
    await message(20000);
    final controller = c.read(salesControllerProvider);
    await controller.settle(
      w,
      await controller.candidatesFor(w),
      over: OverBy.changeByMpesa,
    );
    expect((await controller.waiting()).single.kind, WaitingKind.change);
    final sent = await message(
      2000,
      minutes: 3,
      direction: TransactionDirection.outflow,
    );
    await controller.matchWaiting();
    final t = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(sent))).getSingle();
    expect(t.kind, TransactionKind.reversal);
    expect(await salesInBooks(c), 18000);
  });

  test('paid more: keep it with the sale', () async {
    final c = container();
    final w = await sell(c, 18000);
    await message(20000);
    final controller = c.read(salesControllerProvider);
    await controller.settle(
      w,
      await controller.candidatesFor(w),
      over: OverBy.keepWithSale,
    );
    expect((await db.select(db.sales).get()).single.totalMinor, 20000);
    expect(await salesInBooks(c), 20000);
  });

  testAppWidgets('the sheet adds up what is ticked', (tester) async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final w = await tester.runAsync(() async {
      final w = await sell(c, 18000);
      await message(10000);
      await message(8000, minutes: 2, name: 'Peter K.');
      return w;
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showChoosePaymentsSheet(context, w!),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await settleFrames(tester);
    await tester.tap(find.text('Grace W. · 100'));
    await tester.pump();
    expect(find.text('That is 80 less than the sale.'), findsOneWidget);
    await tester.tap(find.text('Peter K. · 80'));
    await tester.pump();
    expect(find.text('80 + 100 = 180. That covers this sale.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('choose-save')));
    await settleFrames(tester);
    final left = await tester.runAsync(
      () => c.read(salesControllerProvider).waiting(),
    );
    expect(left, isEmpty);
  });
}
