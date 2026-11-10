import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/category_seeds.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/data/repositories/stock_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/spaces/space_categories.dart';
import 'package:pesaclarity/src/features/books/application/books_providers.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/sales/presentation/sell_screen.dart';
import 'package:pesaclarity/src/features/stock/presentation/count_stock_screen.dart';
import 'package:pesaclarity/src/features/stock/presentation/item_screen.dart';
import 'package:pesaclarity/src/features/stock/presentation/stock_screen.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  final now = eat(2026, 11, 5, 9);

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

  Future<int> tomatoes(ProviderContainer c) => c
      .read(stockRepositoryProvider)
      .add(
        kind: ItemKind.product,
        name: 'Tomatoes',
        unit: 'kg',
        priceMinor: 12000,
        costMinor: 8000,
        stockMilli: 6000,
        warnBelowMilli: 5000,
        at: now,
      );

  test('a product starts with its stock, and the books own it', () async {
    final c = container();
    await tomatoes(c);
    final item = (await c.read(stockRepositoryProvider).items()).single;
    expect(item.stockMilli, 6000);
    expect(item.averageCostMinor, 8000);
    final books = await c.read(booksProvider.future);
    expect(books.unbalanced, isEmpty);
    expect(books.balanceOf(BookAccount.stock, currency: 'KES'), 48000);
  });

  test('restocking moves the average cost; it is stock, not a cost', () async {
    final c = container();
    final id = await tomatoes(c);
    await c
        .read(salesControllerProvider)
        .bought(
          amountMinor: 78000,
          method: SalePaymentMethod.cash,
          categoryId: await ensureCategory(db, stockSeed),
          itemId: id,
          quantityMilli: 10000,
        );
    final item = (await c.read(stockRepositoryProvider).items()).single;
    expect(item.stockMilli, 16000);
    expect(item.averageCostMinor, 7875);
    final books = await c.read(booksProvider.future);
    expect(books.unbalanced, isEmpty);
    expect(books.balanceOf(BookAccount.stock, currency: 'KES'), 126000);
    final stockCost = BookAccount.category(
      await ensureCategory(db, stockSeed),
      income: false,
    );
    expect(books.balanceOf(stockCost, currency: 'KES'), 0);
  });

  test('selling takes stock out at the average cost', () async {
    final c = container();
    final id = await tomatoes(c);
    await c
        .read(salesControllerProvider)
        .sell(
          [const SalePart(SalePaymentMethod.cash, 24000)],
          lines: [
            SaleLine(
              itemId: id,
              name: 'Tomatoes, kg',
              quantityMilli: 2000,
              totalMinor: 24000,
            ),
          ],
        );
    final item = (await c.read(stockRepositoryProvider).items()).single;
    expect(item.stockMilli, 4000);
    final books = await c.read(booksProvider.future);
    expect(books.unbalanced, isEmpty);
    expect(books.balanceOf(BookAccount.costOfSales, currency: 'KES'), 16000);
    expect(books.balanceOf(BookAccount.stock, currency: 'KES'), 32000);
    expect(
      books.profit(
        currency: 'KES',
        from: eat(2026, 11, 1, 0),
        to: eat(2026, 11, 6, 0),
      ),
      8000,
    );
    expect(await db.select(db.saleLines).get(), hasLength(1));
  });

  test('a count keeps the difference as a cost, unless miscounted', () async {
    final c = container();
    final id = await tomatoes(c);
    final repo = c.read(stockRepositoryProvider);
    await repo.count(
      id,
      countedMilli: 5000,
      reason: CountReason.spoiled,
      at: now,
    );
    var books = await c.read(booksProvider.future);
    expect(books.balanceOf(BookAccount.stockLosses, currency: 'KES'), 8000);
    await repo.count(
      id,
      countedMilli: 5500,
      reason: CountReason.miscounted,
      at: now,
    );
    books = await c.read(booksProvider.future);
    expect(books.unbalanced, isEmpty);
    expect(books.balanceOf(BookAccount.stockLosses, currency: 'KES'), 8000);
    expect((await repo.items()).single.stockMilli, 5500);
    expect(await repo.moves(id), hasLength(3));
  });

  group('Stock and counting', () {
    Future<ProviderContainer> pump(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      await tester.runAsync(() async {
        await tomatoes(c);
        await c
            .read(stockRepositoryProvider)
            .add(
              kind: ItemKind.service,
              name: 'Delivery',
              priceMinor: 5000,
              at: now,
            );
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => AmountsHiddenScope(child: child!),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => screen)),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settleFrames(tester);
      return c;
    }

    testAppWidgets('Stock shows all, or products or services', (tester) async {
      await pump(tester, const StockScreen());
      expect(find.text('Tomatoes'), findsOneWidget);
      expect(find.text('Delivery'), findsOneWidget);

      Future<void> show(String kind) async {
        await tester.tap(find.byKey(const Key('stock-kind')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('stock-kind-$kind')));
        await tester.pumpAndSettle();
      }

      await show('service');
      expect(find.text('Tomatoes'), findsNothing);
      expect(find.text('Delivery'), findsOneWidget);
      await show('product');
      expect(find.text('Tomatoes'), findsOneWidget);
      expect(find.text('Delivery'), findsNothing);
      await show('all');
      expect(find.text('Tomatoes'), findsOneWidget);
      expect(find.text('Delivery'), findsOneWidget);
    });

    testAppWidgets('Add sits in the title row, beside Count stock', (
      tester,
    ) async {
      await pump(tester, const StockScreen());
      expect(find.byKey(const Key('count-stock')), findsOneWidget);
      expect(find.text('Add an item'), findsNothing);

      await tester.tap(find.byTooltip('Add an item'));
      await tester.pumpAndSettle();
      expect(find.text('Add an item'), findsOneWidget);
      expect(find.byKey(const Key('item-name')), findsOneWidget);
    });

    testAppWidgets('an item hides its price, cost and profit behind the eye', (
      tester,
    ) async {
      await pump(tester, const ItemScreen(itemId: 1));
      expect(find.text('Tomatoes'), findsWidgets);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);

      await tester.tap(find.byKey(const Key('amounts-eye')));
      await tester.pumpAndSettle();
      expect(find.text('120'), findsNothing);
      expect(find.text('80'), findsNothing);
      expect(find.text('•••••'), findsWidgets);
    });

    testAppWidgets('a count keeps why: chosen from a menu when less', (
      tester,
    ) async {
      final c = await pump(tester, const CountStockScreen());
      final id = (await tester.runAsync(
        () => c.read(stockRepositoryProvider).items(),
      ))!.firstWhere((i) => i.name == 'Tomatoes').id;

      // More than the records: miscounted is the one reason.
      await tester.enterText(find.byKey(Key('count-$id')), '7');
      await tester.pump();
      expect(find.byKey(Key('reason-$id')), findsNothing);
      expect(find.byKey(Key('reason-$id-miscounted')), findsOneWidget);

      await tester.enterText(find.byKey(Key('count-$id')), '5');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(Key('reason-$id')),
          matching: find.text('Spoiled'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(Key('reason-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('reason-$id-lost')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(Key('reason-$id')),
          matching: find.text('Lost'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('count-save')));
      await settleFrames(tester);
      final moves = await tester.runAsync(
        () => c.read(stockRepositoryProvider).moves(id),
      );
      expect(moves!.map((m) => m.reason), contains(CountReason.lost));
      expect(
        (await tester.runAsync(() => c.read(stockRepositoryProvider).items()))!
            .firstWhere((i) => i.id == id)
            .stockMilli,
        5000,
      );
    });

    testAppWidgets('a count that turns into more is kept as miscounted', (
      tester,
    ) async {
      final c = await pump(tester, const CountStockScreen());
      final id = (await tester.runAsync(
        () => c.read(stockRepositoryProvider).items(),
      ))!.firstWhere((i) => i.name == 'Tomatoes').id;

      await tester.enterText(find.byKey(Key('count-$id')), '5');
      await tester.pump();
      await tester.tap(find.byKey(Key('reason-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('reason-$id-lost')));
      await tester.pumpAndSettle();
      // Then there turns out to be more than the records.
      await tester.enterText(find.byKey(Key('count-$id')), '7');
      await tester.pump();
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(Key('reason-$id-miscounted')))
            .selected,
        isTrue,
      );
      expect(
        find.text('The records are corrected, with no cost.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('count-save')));
      await settleFrames(tester);
      final moves = await tester.runAsync(
        () => c.read(stockRepositoryProvider).moves(id),
      );
      expect(moves!.map((m) => m.reason), contains(CountReason.miscounted));
      expect(moves.map((m) => m.reason), isNot(contains(CountReason.lost)));
    });
  });

  group('Sell with items', () {
    Future<void> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
      await tester.runAsync(() async {
        await tomatoes(c);
        await c
            .read(stockRepositoryProvider)
            .add(
              kind: ItemKind.service,
              name: 'Delivery',
              priceMinor: 5000,
              at: now,
            );
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const SellScreen()),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await settleFrames(tester);
    }

    testAppWidgets('tiles add up, and Pay sells the lines', (tester) async {
      await pump(tester);
      expect(find.text('Tomatoes'), findsOneWidget);
      expect(find.text('120 / kg'), findsOneWidget);
      expect(find.text('Delivery'), findsOneWidget);
      expect(find.byKey(const Key('tile-other')), findsOneWidget);

      await tester.tap(find.text('Tomatoes'));
      await tester.tap(find.text('Tomatoes'));
      await tester.tap(find.text('Delivery'));
      await tester.pump();
      expect(find.text('2 items'), findsOneWidget);
      expect(find.text('KES 290'), findsOneWidget);

      await tester.tap(find.byKey(const Key('sell-pay')));
      await settleFrames(tester);
      expect(find.text('Pay KES 290'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.remove).first);
      await tester.pump();
      expect(find.text('Pay KES 170'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pay-done')));
      await settleFrames(tester);
      final items = await tester.runAsync(() => db.select(db.items).get());
      final kept = items!.firstWhere((i) => i.name == 'Tomatoes');
      expect(kept.stockMilli, 5000);
      final lines = await tester.runAsync(() => db.select(db.saleLines).get());
      expect(lines, hasLength(2));
    });
  });
}
