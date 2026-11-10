import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/data/repositories/stock_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/spaces/space_categories.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/books/application/books_providers.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/sales/presentation/sell_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  final now = eat(2026, 11, 5, 14, 40);

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

  Future<int> received(int accountId, int amount, DateTime at) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: accountId,
          occurredAt: at,
          amountMinor: amount,
          direction: TransactionDirection.inflow,
          kind: const Value(TransactionKind.received),
          source: TransactionSource.sms,
          counterpartyName: const Value('Grace W.'),
        ),
      );

  Future<List<TransactionRecord>> transactions() =>
      db.select(db.transactions).get();

  Future<int> salesId() async => (await (db.select(
    db.categories,
  )..where((c) => c.key.equals(salesCategoryKey))).getSingle()).id;

  group('selling', () {
    test('cash goes into the drawer as a sale', () async {
      final c = container();
      await c.read(salesControllerProvider).sell([
        const SalePart(SalePaymentMethod.cash, 35000),
      ]);
      final cash = await (db.select(
        db.accounts,
      )..where((a) => a.type.equalsValue(AccountType.cash))).getSingle();
      final t = (await transactions()).single;
      expect(t.accountId, cash.id);
      expect(t.amountMinor, 35000);
      expect(t.direction, TransactionDirection.inflow);
      expect(t.categoryOverrideId, await salesId());
      expect(await c.read(salesControllerProvider).waiting(), isEmpty);
    });

    test('M-Pesa waits, then matches the message when it comes', () async {
      final c = container();
      final account = await mpesa();
      final outcome = await c.read(salesControllerProvider).sell([
        const SalePart(SalePaymentMethod.mpesa, 18000),
      ]);
      expect(outcome.matched, isEmpty);
      expect(await c.read(salesControllerProvider).waiting(), hasLength(1));

      final id = await received(
        account,
        18000,
        now.add(const Duration(minutes: 1)),
      );
      final matched = await c.read(salesControllerProvider).matchWaiting();
      expect(matched.values.single.id, id);
      expect(await c.read(salesControllerProvider).waiting(), isEmpty);
      final t = (await transactions()).single;
      expect(t.categoryOverrideId, await salesId());
    });

    test('a payment already in matches when the sale is saved', () async {
      final c = container();
      final account = await mpesa();
      await received(account, 18000, now.subtract(const Duration(minutes: 2)));
      final outcome = await c.read(salesControllerProvider).sell([
        const SalePart(SalePaymentMethod.mpesa, 18000),
      ]);
      expect(outcome.matched.single.counterpartyName, 'Grace W.');
    });

    test('credit adds what the customer owes and counts as a sale', () async {
      final c = container();
      await c.read(salesControllerProvider).sell(
        [
          const SalePart(SalePaymentMethod.cash, 10000),
          const SalePart(SalePaymentMethod.credit, 8000),
        ],
        credit: CreditTerms(
          customer: 'Otieno',
          dueDate: CalendarDate(2026, 11, 12),
        ),
      );
      final loan = (await db.select(db.lentLoans).get()).single;
      expect(loan.person, 'Otieno');
      expect(loan.amountMinor, 8000);
      expect(CalendarDate.local(loan.dueDate!), CalendarDate(2026, 11, 12));

      final books = await c.read(booksProvider.future);
      expect(books.unbalanced, isEmpty);
      expect(books.balanceOf(BookAccount.owedToYou, currency: 'KES'), 8000);
      final today = await c.read(salesTodayProvider.future);
      expect(today.day.byWay, {
        SalePaymentMethod.cash: 10000,
        SalePaymentMethod.credit: 8000,
      });
    });

    test('a waiting part can be paid in cash or removed', () async {
      final c = container();
      await mpesa();
      final controller = c.read(salesControllerProvider);
      await controller.sell([const SalePart(SalePaymentMethod.mpesa, 18000)]);
      await controller.sell([const SalePart(SalePaymentMethod.bank, 5000)]);
      final [first, second] = await controller.waiting();

      await controller.paidInCash(first);
      expect((await transactions()).single.amountMinor, 18000);
      await controller.removeWaiting(second);
      expect(await controller.waiting(), isEmpty);
      expect(await db.select(db.sales).get(), hasLength(1));
    });
  });

  group('the Sell screen', () {
    Future<void> pump(WidgetTester tester) async {
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
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SellScreen(),
                      ),
                    ),
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

    Future<void> key(WidgetTester tester, String k) async {
      await tester.tap(find.byKey(Key('sell-key-$k')));
      await tester.pump();
    }

    /// Opens the drop-down [menu] and picks [choice] in it.
    Future<void> choose(WidgetTester tester, String menu, String choice) async {
      await tester.tap(find.byKey(Key(menu)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key(choice)));
      await tester.pumpAndSettle();
    }

    testAppWidgets('typing an amount and paying cash saves the sale', (
      tester,
    ) async {
      await pump(tester);
      for (final k in ['3', '5', '0']) {
        await key(tester, k);
      }
      Text amount() =>
          tester.widget<Text>(find.byKey(const Key('sell-amount')));
      expect(amount().data, 'KES 350');
      await key(tester, '⌫');
      await key(tester, '00');
      expect(amount().data, 'KES 3,500');

      await tester.tap(find.byKey(const Key('sell-pay')));
      await settleFrames(tester);
      expect(find.text('Pay KES 3,500'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('pay-given')), '4000');
      await tester.pump();
      expect(find.text('Change: KES 500'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pay-done')));
      await settleFrames(tester);
      expect(find.text('Sale saved.'), findsOneWidget);
      expect(find.byType(SellScreen), findsNothing);
      final t = await tester.runAsync(transactions);
      expect(t!.single.amountMinor, 350000);
    });

    testAppWidgets('on credit asks who will pay', (tester) async {
      await pump(tester);
      await key(tester, '5');
      await key(tester, '00');
      await tester.tap(find.byKey(const Key('sell-pay')));
      await settleFrames(tester);
      await choose(tester, 'pay-way', 'pay-credit');
      await tester.tap(find.byKey(const Key('pay-done')));
      await tester.pump();
      expect(find.text('Enter who will pay, such as Otieno.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('pay-customer')), 'Otieno');
      await tester.tap(find.byKey(const Key('pay-done')));
      await settleFrames(tester);
      final loans = await tester.runAsync(() => db.select(db.lentLoans).get());
      expect(loans!.single.person, 'Otieno');
      expect(loans.single.amountMinor, 50000);
    });

    testAppWidgets('M-Pesa says it will match the message', (tester) async {
      await pump(tester);
      await key(tester, '1');
      await key(tester, '8');
      await key(tester, '0');
      await tester.tap(find.byKey(const Key('sell-pay')));
      await settleFrames(tester);
      await choose(tester, 'pay-way', 'pay-mpesa');
      expect(
        find.textContaining('Waiting for the M-Pesa message for KES 180'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('pay-done')));
      await settleFrames(tester);
      expect(
        find.text(
          'Sale saved. It will match the M-Pesa message when it comes.',
        ),
        findsOneWidget,
      );
    });

    testAppWidgets('split: part now, the rest on credit due today', (
      tester,
    ) async {
      await pump(tester);
      await key(tester, '5');
      await key(tester, '00');
      await tester.tap(find.byKey(const Key('sell-pay')));
      await settleFrames(tester);
      await choose(tester, 'pay-way', 'pay-split');
      await tester.enterText(find.byKey(const Key('pay-now')), '200');
      await choose(tester, 'pay-now-menu', 'pay-now-mpesa');
      // The rest goes another way from the part paid now: cash.
      expect(
        find.descendant(
          of: find.byKey(const Key('pay-rest-menu')),
          matching: find.text('Cash'),
        ),
        findsOneWidget,
      );
      await choose(tester, 'pay-rest-menu', 'pay-rest-credit');
      await tester.enterText(find.byKey(const Key('pay-customer')), 'Otieno');
      await choose(tester, 'pay-by', 'pay-by-today');
      await tester.tap(find.byKey(const Key('pay-done')));
      await settleFrames(tester);

      final loan = await tester.runAsync(
        () => db.select(db.lentLoans).getSingle(),
      );
      expect(loan!.person, 'Otieno');
      expect(loan.amountMinor, 30000);
      expect(CalendarDate.local(loan.dueDate!), CalendarDate(2026, 11, 5));
    });
  });

  group('Sell by group', () {
    /// Sell with Tomatoes and Delivery, and with [grouped] Onions in a
    /// Vegetables group too.
    Future<void> pump(WidgetTester tester, {bool grouped = false}) async {
      tester.view.physicalSize = const Size(900, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        final stock = container().read(stockRepositoryProvider);
        await stock.add(
          kind: ItemKind.product,
          name: 'Tomatoes',
          priceMinor: 12000,
          at: now,
        );
        await stock.add(
          kind: ItemKind.service,
          name: 'Delivery',
          priceMinor: 5000,
          at: now,
        );
        if (grouped) {
          await stock.add(
            kind: ItemKind.product,
            name: 'Onions',
            priceMinor: 8000,
            grouping: 'Vegetables',
            at: now,
          );
        }
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(theme: AppTheme.light, home: const SellScreen()),
        ),
      );
      await settleFrames(tester);
    }

    testAppWidgets('one group shows as two segments with All', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('sell-groups')), findsNothing);
      await tester.tap(find.byKey(const Key('sell-group-Services')));
      await tester.pump();
      expect(find.text('Tomatoes'), findsNothing);
      expect(find.text('Delivery'), findsOneWidget);
    });

    testAppWidgets('more groups show as a menu', (tester) async {
      await pump(tester, grouped: true);
      Future<void> show(String group) async {
        await tester.tap(find.byKey(const Key('sell-groups')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('sell-group-$group')));
        await tester.pumpAndSettle();
      }

      expect(find.byType(ChoiceChip), findsNothing);
      await show('Vegetables');
      expect(find.text('Onions'), findsOneWidget);
      expect(find.text('Tomatoes'), findsNothing);
      expect(find.text('Delivery'), findsNothing);
      await show('Services');
      expect(find.text('Delivery'), findsOneWidget);
      expect(find.text('Onions'), findsNothing);
      await show('all');
      for (final name in ['Tomatoes', 'Onions', 'Delivery']) {
        expect(find.text(name), findsOneWidget);
      }
    });
  });
}
