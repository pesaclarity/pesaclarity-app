import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/stock_repository.dart';
import 'package:pesaclarity/src/data/repositories/tabs_repository.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/close/presentation/close_day_screen.dart';
import 'package:pesaclarity/src/features/sales/presentation/sell_screen.dart';
import 'package:pesaclarity/src/features/tabs/presentation/tab_screens.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  final now = eat(2026, 11, 13, 20, 40);

  setUp(() {
    UserTimeZone.set(nairobiUtcOffset);
    db = openTestDatabase();
  });
  tearDown(UserTimeZone.resetToDevice);

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => now),
  ];

  Future<int> lager(ProviderContainer c) => c
      .read(stockRepositoryProvider)
      .add(
        kind: ItemKind.product,
        name: 'Lager',
        unit: 'Bottle',
        priceMinor: 20000,
        costMinor: 15000,
        stockMilli: 30000,
        at: now,
      );

  SaleLine lagers(int item, int n) => SaleLine(
    itemId: item,
    name: 'Lager, Bottle',
    quantityMilli: n * 1000,
    totalMinor: n * 20000,
  );

  Future<int> stockOf(int item) async => (await (db.select(
    db.items,
  )..where((i) => i.id.equals(item))).getSingle()).stockMilli;

  test('a tab adds rounds and holds stock without selling it', () async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final item = await lager(c);
    final tabs = c.read(tabsRepositoryProvider);
    final id = await tabs.start('Table 4', at: now);
    await tabs.add(id, [lagers(item, 2)], at: now);
    await tabs.add(id, [lagers(item, 4)], at: eat(2026, 11, 13, 21, 45));

    final open = (await tabs.open()).single;
    expect(open.name, 'Table 4');
    expect(open.itemCount, 6);
    expect(open.totalMinor, 120000);
    expect(await tabs.held(), {item: 6000});
    expect(await stockOf(item), 30000);

    final merged = TabScreen.asSale(await tabs.lines(id));
    expect(merged.single.quantityMilli, 6000);
    expect(merged.single.totalMinor, 120000);

    await tabs.close(id, at: now);
    expect(await tabs.open(), isEmpty);
    expect(await tabs.held(), isEmpty);
  });

  test('closing a tab with nothing on it drops it', () async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final tabs = c.read(tabsRepositoryProvider);
    final id = await tabs.start('Patio', at: now);
    await tabs.close(id, at: now);
    expect(await db.select(db.tabs).get(), isEmpty);
  });

  Future<void> open(
    WidgetTester tester,
    ProviderContainer c,
    Widget screen,
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
                onPressed: () =>
                    Navigator.of(context)
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
  }

  testAppWidgets('Sell: add to a new tab, then pay and close it', (
    tester,
  ) async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    final item = (await tester.runAsync(() => lager(c)))!;
    await open(tester, c, const SellScreen());

    await tester.tap(find.text('Lager'));
    await tester.tap(find.text('Lager'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('sell-add-to-tab')));
    await settleFrames(tester);
    expect(find.text('2 items · KES 400'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('tab-new')), 'Table 4');
    await tester.tap(find.byKey(const Key('tab-add')));
    await settleFrames(tester);
    expect(find.text('Added to Table 4.'), findsOneWidget);
    expect(await tester.runAsync(() => stockOf(item)), 30000);

    // Back on Sell, the tile counts what the tab holds.
    await tester.tap(find.text('Open'));
    await settleFrames(tester);
    expect(find.text('28 Bottles'), findsOneWidget);
    expect(find.text('Open tabs · 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sell-open-tabs')));
    await settleFrames(tester);
    expect(find.text('On open tabs'), findsOneWidget);
    expect(find.text('2 items · since 20:40'), findsOneWidget);

    await tester.tap(find.text('Table 4'));
    await settleFrames(tester);
    expect(find.text('Lager × 2'), findsOneWidget);
    expect(find.text('Pay and close · KES 400'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab-pay')));
    await settleFrames(tester);
    await tester.tap(find.byKey(const Key('pay-done')));
    await settleFrames(tester);

    expect(await tester.runAsync(() => stockOf(item)), 28000);
    final lines = (await tester.runAsync(() => db.select(db.saleLines).get()))!;
    expect(lines.single.quantityMilli, 2000);
    final tabs = (await tester.runAsync(() => db.select(db.tabs).get()))!;
    expect(tabs.single.closedAt, isNotNull);
  });

  testAppWidgets('Close the day: open tabs are not missed', (tester) async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await tester.runAsync(() async {
      final item = await lager(c);
      final tabs = c.read(tabsRepositoryProvider);
      for (final (name, n) in [('Table 4', 2), ('Peter Kamau', 3)]) {
        final id = await tabs.start(name, at: now);
        await tabs.add(id, [lagers(item, n)], at: now);
      }
    });
    await open(tester, c, const CloseDayScreen());
    expect(
      find.text(
        '2 tabs are still open, KES 1,000: Table 4 and Peter Kamau. Settle '
        'them, or keep them open for the next day.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const Key('close-see-tabs')));
    await tester.tap(find.byKey(const Key('close-see-tabs')));
    await settleFrames(tester);
    expect(find.text('Open tabs'), findsOneWidget);
  });
}
