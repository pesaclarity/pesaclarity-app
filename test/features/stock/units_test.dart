import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/data/repositories/stock_repository.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/sales/presentation/records_sheets.dart';
import 'package:pesaclarity/src/features/sales/presentation/sell_screen.dart';
import 'package:pesaclarity/src/features/stock/presentation/item_sheet.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  final now = eat(2026, 11, 13, 21);

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

  /// Whisky counted in bottles, sold by the tot and the double too.
  Future<({int item, int tot, int double})> whisky(ProviderContainer c) async {
    final stock = c.read(stockRepositoryProvider);
    final item = await stock.add(
      kind: ItemKind.product,
      name: 'Whisky, 750 ml',
      unit: 'Bottle',
      priceMinor: 350000,
      costMinor: 240000,
      stockMilli: 5400,
      at: now,
    );
    final tot = await stock.addMeasure(
      item,
      name: 'Tot, 25 ml',
      units: 30,
      bases: 1,
      priceMinor: 15000,
    );
    final double = await stock.addMeasure(
      item,
      name: 'Double, 50 ml',
      units: 15,
      bases: 1,
      priceMinor: 28000,
    );
    return (item: item, tot: tot, double: double);
  }

  Future<int> lager(ProviderContainer c) async {
    final stock = c.read(stockRepositoryProvider);
    final item = await stock.add(
      kind: ItemKind.product,
      name: 'Lager',
      unit: 'Bottle',
      priceMinor: 20000,
      costMinor: 15000,
      stockMilli: 30000,
      at: now,
    );
    await stock.addMeasure(item, name: 'Crate', units: 1, bases: 24);
    return item;
  }

  Future<int> stockOf(int item) async => (await (db.select(
    db.items,
  )..where((i) => i.id.equals(item))).getSingle()).stockMilli;

  test('tots sold one by one take whole bottles out exactly', () async {
    final c = container();
    final w = await whisky(c);
    final controller = c.read(salesControllerProvider);
    for (var i = 0; i < 30; i++) {
      await controller.sell(
        [const SalePart(SalePaymentMethod.cash, 15000)],
        lines: [
          SaleLine(
            itemId: w.item,
            measureId: w.tot,
            name: 'Whisky, 750 ml · Tot, 25 ml',
            quantityMilli: 1000,
            totalMinor: 15000,
          ),
        ],
      );
    }
    expect(await stockOf(w.item), 4400);

    // Reports count it in bottles.
    final sold = await c
        .read(stockRepositoryProvider)
        .soldLines(from: eat(2026, 11, 13, 0), to: eat(2026, 11, 14, 0));
    expect(sold.fold(0, (sum, l) => sum + l.quantityMilli), 1000);
  });

  test('a count sets stock exactly and starts tots afresh', () async {
    final c = container();
    final w = await whisky(c);
    await c
        .read(salesControllerProvider)
        .sell(
          [const SalePart(SalePaymentMethod.cash, 15000)],
          lines: [
            SaleLine(
              itemId: w.item,
              measureId: w.tot,
              name: 'Whisky, 750 ml · Tot, 25 ml',
              quantityMilli: 1000,
              totalMinor: 15000,
            ),
          ],
        );
    final tot = await (db.select(
      db.itemMeasures,
    )..where((m) => m.id.equals(w.tot))).getSingle();
    expect(tot.carry, isNot(0));
    await c
        .read(stockRepositoryProvider)
        .count(
          w.item,
          countedMilli: 5000,
          reason: CountReason.miscounted,
          at: now,
        );
    final after = await (db.select(
      db.itemMeasures,
    )..where((m) => m.id.equals(w.tot))).getSingle();
    expect(after.carry, 0);
    expect(await stockOf(w.item), 5000);
  });

  test('measures list smallest first, and a removed one is gone', () async {
    final c = container();
    final w = await whisky(c);
    final stock = c.read(stockRepositoryProvider);
    final ways = (await stock.measures())[w.item]!;
    expect(ways.map((m) => m.name), ['Tot, 25 ml', 'Double, 50 ml']);
    await stock.removeMeasure(w.double);
    expect((await stock.measures())[w.item]!.single.name, 'Tot, 25 ml');
  });

  Future<void> open(
    WidgetTester tester,
    ProviderContainer c,
    Object? Function(BuildContext) screen,
  ) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => screen(context),
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

  testAppWidgets('Sell: choose tots, a double or a bottle', (tester) async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final w = (await tester.runAsync(() => whisky(c)))!;
    await tester.runAsync(() => lager(c));
    await open(
      tester,
      c,
      (context) => Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const SellScreen())),
    );
    expect(find.text('From 150'), findsOneWidget);
    expect(find.text('5 bottles and 12 tots'), findsOneWidget);
    expect(find.text('1 crate and 6 left'), findsOneWidget);

    await tester.tap(find.text('Whisky, 750 ml'));
    await settleFrames(tester);
    expect(find.text('5 bottles and 12 tots left'), findsOneWidget);
    await tester.tap(find.byKey(Key('way-more-${w.tot}')));
    await tester.tap(find.byKey(Key('way-more-${w.tot}')));
    await tester.tap(find.byKey(Key('way-more-${w.double}')));
    await tester.pump();
    expect(find.text('Add · KES 580'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sell-ways-add')));
    await settleFrames(tester);
    expect(find.text('2 items'), findsOneWidget);
    expect(find.text('KES 580'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sell-pay')));
    await settleFrames(tester);
    await tester.tap(find.byKey(const Key('pay-done')));
    await settleFrames(tester);
    final lines = (await tester.runAsync(() => db.select(db.saleLines).get()))!;
    expect(lines.map((l) => l.measureId), unorderedEquals([w.tot, w.double]));
    // Two tots and a double are four tots: 4/30 of a bottle, with the
    // part of a thousandth kept for the next sale.
    expect(await tester.runAsync(() => stockOf(w.item)), 5400 - 132);
  });

  testAppWidgets('Bought: crates of 24 go into stock as bottles', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final item = (await tester.runAsync(() => lager(c)))!;
    await open(tester, c, (context) => showBoughtSheet(context, itemId: item));
    await tester.tap(find.byKey(const Key('bought-of')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crates of 24').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('bought-quantity')), '3');
    await tester.enterText(find.byKey(const Key('bought-amount')), '11400');
    await tester.pump();
    expect(
      find.text(
        'Stock goes to 4 crates and 6 bottles (102 bottles). Each bottle now '
        'costs you about KES 156.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('bought-save')));
    await settleFrames(tester);
    expect(await tester.runAsync(() => stockOf(item)), 102000);
  });

  testAppWidgets('Add an item: sell it another way', (tester) async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await open(tester, c, showItemSheet);
    await tester.enterText(
      find.byKey(const Key('item-name')),
      'Whisky, 750 ml',
    );
    await tester.enterText(find.byKey(const Key('item-unit')), 'Bottle');
    await tester.enterText(find.byKey(const Key('item-stock')), '6');
    await tester.enterText(find.byKey(const Key('item-price')), '3500');
    await tester.pump();
    await tester.tap(find.byKey(const Key('item-add-measure')));
    await settleFrames(tester);
    expect(find.text('Whisky, 750 ml · counted in bottles'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('measure-name')), 'Tot, 25 ml');
    await tester.enterText(find.byKey(const Key('measure-count')), '30');
    await tester.enterText(find.byKey(const Key('measure-price')), '150');
    await tester.pump();
    expect(
      find.text(
        'Each tot sold takes 1/30 of a bottle out of stock. 30 tots bring in '
        'KES 4,500 a bottle, against KES 3,500 for the whole bottle.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('measure-save')));
    await settleFrames(tester);
    expect(find.text('30 in a bottle'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('item-cost')), '2400');
    await tester.pump();
    expect(find.text('Each tot then costs you about KES 80.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('item-save')));
    await tester.tap(find.byKey(const Key('item-save')));
    await settleFrames(tester);

    final ways = (await tester.runAsync(
      () => db.select(db.itemMeasures).get(),
    ))!;
    expect(ways.single.name, 'Tot, 25 ml');
    expect(ways.single.units, 30);
    expect(ways.single.priceMinor, 15000);
  });
}
