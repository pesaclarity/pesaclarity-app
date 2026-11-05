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
