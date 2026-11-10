import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/category_seeds.dart';
import 'package:pesaclarity/src/data/repositories/debts_repository.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/data/repositories/stock_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/spaces/space_categories.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/books/application/books_providers.dart';
import 'package:pesaclarity/src/features/lending/application/lending_providers.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/sales/presentation/records_sheets.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  final now = eat(2026, 11, 5, 9, 30);
  final today = CalendarDate(2026, 11, 5);

  setUp(() => db = openTestDatabase());

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => now),
  ];

  ProviderContainer container() {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    return c;
  }

  Future<int> mpesa() => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingDate: eat(2026, 11, 1, 0),
        ),
      );

  Future<int> message(
    int accountId,
    int amount, {
    required TransactionDirection direction,
  }) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: accountId,
          occurredAt: now.add(const Duration(minutes: 1)),
          amountMinor: amount,
          direction: direction,
          kind: Value(
            direction == TransactionDirection.inflow
                ? TransactionKind.received
                : TransactionKind.till,
          ),
          source: TransactionSource.sms,
        ),
      );

  Future<TransactionRecord> transaction(int id) =>
      (db.select(db.transactions)..where((t) => t.id.equals(id))).getSingle();

  Future<int> categoryKeyed(String key) async => (await (db.select(
    db.categories,
  )..where((c) => c.key.equals(key))).getSingle()).id;

  test('stock bought in cash goes out of the drawer as stock', () async {
    final c = container();
    final stock = await ensureCategory(db, stockSeed);
    await c
        .read(salesControllerProvider)
        .bought(
          amountMinor: 240000,
          method: SalePaymentMethod.cash,
          categoryId: stock,
          supplier: 'Wakulima market',
        );
    final t = (await db.select(db.transactions).get()).single;
    expect(t.direction, TransactionDirection.outflow);
    expect(t.amountMinor, 240000);
    expect(t.categoryOverrideId, stock);
    expect(t.counterpartyName, 'Wakulima market');
  });

  test('stock bought by M-Pesa files the message when it comes', () async {
    final c = container();
    final account = await mpesa();
    final stock = await ensureCategory(db, stockSeed);
    final controller = c.read(salesControllerProvider);
    await controller.bought(
      amountMinor: 240000,
      method: SalePaymentMethod.mpesa,
      categoryId: stock,
    );
    expect(await controller.waiting(), hasLength(1));
    final id = await message(
      account,
      240000,
      direction: TransactionDirection.outflow,
    );
    await controller.matchWaiting();
    expect(await controller.waiting(), isEmpty);
    expect((await transaction(id)).categoryOverrideId, stock);
  });

  test('bought to pay later: the supplier is owed, then paid', () async {
    final c = container();
    final stock = await ensureCategory(db, stockSeed);
    final controller = c.read(salesControllerProvider);
    await controller.bought(
      amountMinor: 450000,
      method: SalePaymentMethod.credit,
      categoryId: stock,
      supplier: 'Wakulima wholesaler',
      dueDate: CalendarDate(2026, 11, 7),
    );
    final debt = (await c.read(debtsRepositoryProvider).debts(today: today))
        .single;
    expect(debt.lender, 'Wakulima wholesaler');
    expect(debt.balanceMinor, 450000);
    expect(debt.type, DebtType.supplier);
    expect(await db.select(db.transactions).get(), isEmpty);

    var books = await c.read(booksProvider.future);
    expect(books.unbalanced, isEmpty);
    expect(
      books.balanceOf(BookAccount.owedToSuppliers, currency: 'KES'),
      450000,
    );

    await controller.paid(
      debtId: debt.id,
      supplier: debt.lender,
      amountMinor: 300000,
      method: SalePaymentMethod.cash,
    );
    final after = (await c.read(debtsRepositoryProvider).debts(today: today))
        .single;
    expect(after.balanceMinor, 150000);
    final t = (await db.select(db.transactions).get()).single;
    expect(t.debtId, debt.id);
    expect(t.categoryOverrideId, await categoryKeyed(supplierPaymentsKey));

    books = await c.read(booksProvider.future);
    expect(books.unbalanced, isEmpty);
    expect(
      books.balanceOf(BookAccount.owedToSuppliers, currency: 'KES'),
      150000,
    );
  });

  test('got paid takes it off what the customer owes, oldest first', () async {
    final c = container();
    final controller = c.read(salesControllerProvider);
    for (final amount in [80000, 50000]) {
      await controller.sell([
        SalePart(SalePaymentMethod.credit, amount),
      ], credit: const CreditTerms(customer: 'Otieno'));
    }
    await controller.gotPaid(
      customer: 'Otieno',
      amountMinor: 100000,
      method: SalePaymentMethod.cash,
    );
    final lent = await c.read(lendingOverviewProvider.future);
    final left = [for (final l in lent.lent) l.status(today).remainingMinor]
      ..sort();
    expect(left, [0, 30000]);

    final books = await c.read(booksProvider.future);
    expect(books.unbalanced, isEmpty);
    expect(books.balanceOf(BookAccount.owedToYou, currency: 'KES'), 30000);
    // Sales stay at what was sold; the payment is not a second sale.
    final sales = await categoryKeyed(salesCategoryKey);
    expect(
      books.balanceOf(
        BookAccount.category(sales, income: true),
        currency: 'KES',
      ),
      130000,
    );
  });

  test('got paid by M-Pesa waits, then counts the message', () async {
    final c = container();
    final account = await mpesa();
    final controller = c.read(salesControllerProvider);
    await controller.sell([
      const SalePart(SalePaymentMethod.credit, 120000),
    ], credit: const CreditTerms(customer: 'Otieno'));
    await controller.gotPaid(
      customer: 'Otieno',
      amountMinor: 120000,
      method: SalePaymentMethod.mpesa,
    );
    expect(await db.select(db.loanPayments).get(), isEmpty);
    final id = await message(
      account,
      120000,
      direction: TransactionDirection.inflow,
    );
    await controller.matchWaiting();
    expect((await db.select(db.loanPayments).get()).single.amountMinor, 120000);
    expect(
      (await transaction(id)).categoryOverrideId,
      await categoryKeyed(customerPaymentsKey),
    );
  });

  group('the sheets', () {
    Future<void> pump(
      WidgetTester tester,
      void Function(BuildContext) open,
    ) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => open(context),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settleFrames(tester);
    }

    /// Opens the drop-down [menu] and picks [choice] in it.
    Future<void> choose(WidgetTester tester, String menu, String choice) async {
      await tester.tap(find.byKey(Key(menu)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(choice)));
      await tester.pumpAndSettle();
    }

    /// Whether the drop-down [menu] shows [text] as its choice.
    Finder showing(String menu, String text) =>
        find.descendant(of: find.byKey(Key(menu)), matching: find.text(text));

    testAppWidgets('Bought to pay later needs the supplier', (tester) async {
      await pump(tester, showBoughtSheet);
      await tester.enterText(find.byKey(const Key('bought-amount')), '4500');
      await choose(tester, 'bought-way-menu', 'bought-way-credit');
      await tester.tap(find.byKey(const Key('bought-save')));
      await tester.pump();
      expect(
        find.text('Enter who you will pay, such as Wakulima wholesaler.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('bought-supplier')),
        'Wakulima wholesaler',
      );
      await tester.tap(find.byKey(const Key('bought-save')));
      await settleFrames(tester);
      expect(find.text('Bought saved.'), findsOneWidget);
      final debts = await tester.runAsync(() => db.select(db.debts).get());
      expect(debts!.single.startingBalanceMinor, 450000);
    });

    testAppWidgets('Bought to pay later keeps when it is due', (tester) async {
      await pump(tester, showBoughtSheet);
      await tester.enterText(find.byKey(const Key('bought-amount')), '4500');
      await choose(tester, 'bought-way-menu', 'bought-way-credit');
      await tester.enterText(
        find.byKey(const Key('bought-supplier')),
        'Wakulima wholesaler',
      );
      expect(showing('due', 'Any time'), findsOneWidget);
      await choose(tester, 'due', 'due-inAWeek');
      expect(showing('due', 'In a week'), findsOneWidget);
      await tester.tap(find.byKey(const Key('bought-save')));
      await settleFrames(tester);
      final due = await tester.runAsync(
        () => db.select(db.debtInstalments).getSingle(),
      );
      expect(CalendarDate.local(due!.dueDate), today.addDays(7));
    });

    testAppWidgets('Bought stock: more than two items are a menu', (
      tester,
    ) async {
      final ids = await tester.runAsync(() async {
        final stock = container().read(stockRepositoryProvider);
        return [
          for (final name in ['Tomatoes', 'Onions', 'Sukuma'])
            await stock.add(
              kind: ItemKind.product,
              name: name,
              priceMinor: 10000,
              costMinor: 6000,
              at: now,
            ),
        ];
      });
      await pump(tester, showBoughtSheet);
      expect(showing('bought-item', 'Other stock'), findsOneWidget);
      expect(find.byKey(const Key('bought-quantity')), findsNothing);
      await choose(tester, 'bought-item', 'bought-item-${ids![1]}');
      expect(showing('bought-item', 'Onions'), findsOneWidget);
      expect(find.byKey(const Key('bought-quantity')), findsOneWidget);
      await choose(tester, 'bought-item', 'bought-item-other');
      expect(find.byKey(const Key('bought-quantity')), findsNothing);
    });

    testAppWidgets('Got paid lists who owes, with the amount', (tester) async {
      await tester.runAsync(
        () => container().read(salesControllerProvider).sell([
          const SalePart(SalePaymentMethod.credit, 120000),
        ], credit: const CreditTerms(customer: 'Otieno')),
      );
      await pump(tester, showGotPaidSheet);
      expect(find.text('Otieno · 1,200'), findsOneWidget);
      await tester.tap(find.byKey(const Key('got-paid-save')));
      await settleFrames(tester);
      expect(find.text('Payment saved.'), findsOneWidget);
      final paid = await tester.runAsync(
        () => db.select(db.loanPayments).get(),
      );
      expect(paid!.single.amountMinor, 120000);
    });

    testAppWidgets('Got paid: more than two customers are a menu', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final controller = container().read(salesControllerProvider);
        for (final (customer, amount) in [
          ('Otieno', 120000),
          ('Wanjiku', 80000),
          ('Kamau', 50000),
        ]) {
          await controller.sell([
            SalePart(SalePaymentMethod.credit, amount),
          ], credit: CreditTerms(customer: customer));
        }
      });
      await pump(tester, showGotPaidSheet);
      expect(find.byKey(const Key('got-paid-who')), findsOneWidget);
      await choose(tester, 'got-paid-who', 'got-paid-Wanjiku');
      expect(showing('got-paid-who', 'Wanjiku · 800'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('got-paid-amount')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '800',
      );
      await tester.tap(find.byKey(const Key('got-paid-save')));
      await settleFrames(tester);
      final paid = await tester.runAsync(() async {
        final payment = await db.select(db.loanPayments).getSingle();
        final loan = await (db.select(
          db.lentLoans,
        )..where((l) => l.id.equals(payment.lentLoanId!))).getSingle();
        return (loan.person, payment.amountMinor);
      });
      expect(paid, ('Wanjiku', 80000));
    });

    testAppWidgets('Paid: more than two suppliers are a menu', (tester) async {
      final debts = await tester.runAsync(() async {
        final controller = container().read(salesControllerProvider);
        final stock = await ensureCategory(db, stockSeed);
        for (final (supplier, amount) in [
          ('Wakulima wholesaler', 450000),
          ('Mzee Juma', 150000),
          ('Bidco depot', 90000),
        ]) {
          await controller.bought(
            amountMinor: amount,
            method: SalePaymentMethod.credit,
            categoryId: stock,
            supplier: supplier,
          );
        }
        return db.select(db.debts).get();
      });
      final juma = debts!.firstWhere((d) => d.lender == 'Mzee Juma');
      await pump(tester, showPaidSheet);
      await choose(tester, 'paid-who', 'paid-${juma.id}');
      expect(showing('paid-who', 'Mzee Juma · 1,500'), findsOneWidget);
      await choose(tester, 'paid-way-menu', 'paid-way-cash');
      await tester.tap(find.byKey(const Key('paid-save')));
      await settleFrames(tester);
      final t = await tester.runAsync(
        () => db.select(db.transactions).getSingle(),
      );
      expect(t!.debtId, juma.id);
      expect(t.amountMinor, 150000);
    });

    testAppWidgets('Paid says when no supplier is owed', (tester) async {
      await pump(tester, showPaidSheet);
      expect(
        find.textContaining('Suppliers you owe show here'),
        findsOneWidget,
      );
    });
  });
}
