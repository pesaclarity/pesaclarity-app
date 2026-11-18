// Business screens for the marketing screenshots: a made-up grocer's day,
// drawn by the app's own widgets (README, Screenshots).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/category_seeds.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/data/repositories/stock_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/spaces/space_categories.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/books/presentation/money_screen.dart';
import 'package:pesaclarity/src/features/close/presentation/close_day_screen.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/documents/presentation/receipt_sheet.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/features/people/presentation/people_screen.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/sales/presentation/sell_screen.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/stock/presentation/stock_screen.dart';
import 'package:pesaclarity/src/features/tax/presentation/tax_screen.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

const _shop = Space(
  id: 'shop',
  name: 'Green Basket Grocers',
  kind: SpaceKind.business,
);

class _Spaces extends SpacesController {
  @override
  Future<List<Space>> build() async => const [Space.personal, _shop];
}

/// The clock the app reads; moved along while the day is recorded.
var _clock = eat(2026, 11, 5, 17, 40);

class _Shop {
  _Shop(this.db, this.c);

  final AppDatabase db;
  final ProviderContainer c;
  late int cash;
  late int mpesa;
  late int bank;
  final items = <String, int>{};
  late int mpesaSaleId;

  SalesController get sales => c.read(salesControllerProvider);

  Future<void> sms(
    DateTime at,
    int shillings,
    String from,
    String code, {
    bool inflow = true,
  }) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: mpesa,
          occurredAt: at,
          amountMinor: kes(shillings),
          direction: inflow
              ? TransactionDirection.inflow
              : TransactionDirection.outflow,
          kind: Value(inflow ? TransactionKind.received : TransactionKind.sent),
          source: TransactionSource.sms,
          counterpartyName: Value(from),
          receiptNo: Value(code),
        ),
      );

  SaleLine line(String name, double qty, int priceShillings, {String? unit}) {
    final q = (qty * 1000).round();
    return SaleLine(
      itemId: items[name],
      name: name,
      quantityMilli: q,
      totalMinor: (kes(priceShillings) * qty).round(),
    );
  }

  Future<void> seed() async {
    final opening = eat(2026, 10, 1, 0);
    Future<int> account(String name, AccountType type, int shillings) => db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: name,
            type: type,
            openingDate: opening,
            openingBalanceMinor: Value(kes(shillings)),
          ),
        );
    cash = await account('Cash', AccountType.cash, 2000);
    mpesa = await account('M-Pesa', AccountType.mpesa, 6500);
    bank = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Equity Bank',
            type: AccountType.bank,
            openingDate: eat(2025, 11, 1, 0),
            openingBalanceMinor: Value(kes(20000)),
          ),
        );

    final settings = c.read(appSettingsRepositoryProvider);
    await settings.writeJson('business.setup', {
      'sells': 'products',
      'recordsStartedAtMs': opening.millisecondsSinceEpoch,
    });
    await settings.writeJson('documents.settings', {
      'phone': '0700 000 000',
      'till': 'Till 000000',
      'place': 'Market Road',
      'nextReceipt': 214,
    });

    final stock = c.read(stockRepositoryProvider);
    Future<void> item(
      String name, {
      String? unit,
      required int price,
      required int cost,
      required double stockQty,
      required double warn,
      String? group,
    }) async {
      items[name] = await stock.add(
        kind: ItemKind.product,
        name: name,
        unit: unit,
        priceMinor: kes(price),
        costMinor: kes(cost),
        stockMilli: (stockQty * 1000).round(),
        warnBelowMilli: (warn * 1000).round(),
        grouping: group,
        at: opening,
      );
    }

    await item(
      'Tomatoes',
      unit: 'kg',
      price: 120,
      cost: 80,
      stockQty: 34,
      warn: 5,
      group: 'Vegetables',
    );
    await item(
      'Onions',
      unit: 'kg',
      price: 100,
      cost: 65,
      stockQty: 26,
      warn: 5,
      group: 'Vegetables',
    );
    await item(
      'Kale',
      unit: 'bunch',
      price: 30,
      cost: 15,
      stockQty: 42,
      warn: 10,
      group: 'Vegetables',
    );
    await item(
      'Cabbage',
      price: 60,
      cost: 35,
      stockQty: 18,
      warn: 6,
      group: 'Vegetables',
    );
    await item(
      'Avocados',
      price: 25,
      cost: 12,
      stockQty: 64,
      warn: 15,
      group: 'Fruit',
    );
    await item(
      'Bananas',
      unit: 'bunch',
      price: 150,
      cost: 100,
      stockQty: 4,
      warn: 4,
      group: 'Fruit',
    );
    await item(
      'Eggs',
      unit: 'tray',
      price: 450,
      cost: 390,
      stockQty: 6,
      warn: 3,
    );
    await item(
      'Milk',
      unit: 'packet',
      price: 65,
      cost: 55,
      stockQty: 20,
      warn: 6,
    );
    items['Delivery'] = await stock.add(
      kind: ItemKind.service,
      name: 'Delivery',
      priceMinor: kes(100),
      at: opening,
    );

    final stockCategory = await ensureCategory(db, stockSeed);

    final salesCategory = await ensureCategory(db, salesSeed);
    final taxCategory = (await (db.select(
      db.categories,
    )..where((x) => x.key.equals('tax'))).getSingle()).id;
    Future<void> banked(
      DateTime at,
      int shillings,
      String name,
      int category, {
      bool inflow = true,
    }) => db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: bank,
            occurredAt: at,
            amountMinor: kes(shillings),
            direction: inflow
                ? TransactionDirection.inflow
                : TransactionDirection.outflow,
            kind: Value(
              inflow ? TransactionKind.received : TransactionKind.sent,
            ),
            source: TransactionSource.sms,
            counterpartyName: Value(name),
            categoryOverrideId: Value(category),
          ),
        );

    // A year of trading banked month by month, its stock and its tax.
    for (var m = 0; m < 11; m++) {
      final month = DateTime.utc(2025, 11 + m);
      final shillings = 92000 + (m * 3700) % 14000;
      await banked(
        eat(month.year, month.month, 28, 17),
        shillings,
        'Sales banked',
        salesCategory,
      );
      await banked(
        eat(month.year, month.month, 28, 18),
        shillings - 9000,
        'FRESH FARM SUPPLIES',
        stockCategory,
        inflow: false,
      );
      final next = DateTime.utc(month.year, month.month + 1);
      await banked(
        eat(next.year, next.month, 18, 10),
        (shillings * 0.015).round(),
        'KRA',
        taxCategory,
        inflow: false,
      );
    }

    // Five weeks in the app before today: cash and M-Pesa sales typed as
    // amounts, and the stock bought for them at the end of the day.
    var code = 1;
    String nextCode() => 'TK${(code++).toString().padLeft(8, '0')}';
    const names = [
      'PETER KAMAU',
      'GRACE WANJIRU',
      'MARY NJERI',
      'JOHN MWANGI',
      'ACHIENG OTIENO',
    ];
    const busy = [0.9, 0.9, 1.0, 1.0, 1.15, 1.3, 0.6];
    for (var d = 0; d < 35; d++) {
      final day = CalendarDate(2026, 10, 1).addDays(d);
      final b = busy[day.weekday - 1];
      final cashShillings = ((1200 + (d * 137) % 500) * b).round();
      final mpesaShillings = ((1900 + (d * 211) % 700) * b).round();
      _clock = eat(day.year, day.month, day.day, 9, 15);
      await sales.sell([SalePart(SalePaymentMethod.cash, kes(cashShillings))]);
      _clock = eat(day.year, day.month, day.day, 13, 5);
      await sms(_clock, mpesaShillings, names[d % names.length], nextCode());
      await sales.sell([
        SalePart(SalePaymentMethod.mpesa, kes(mpesaShillings)),
      ]);
      _clock = eat(day.year, day.month, day.day, 18, 30);
      await sales.bought(
        amountMinor: kes(cashShillings - 40),
        method: SalePaymentMethod.cash,
        categoryId: stockCategory,
        note: 'Vegetables from the market',
      );
      final stockMpesa = mpesaShillings - 450;
      await sms(
        _clock,
        stockMpesa,
        'FRESH FARM SUPPLIES',
        nextCode(),
        inflow: false,
      );
      await sales.bought(
        amountMinor: kes(stockMpesa),
        method: SalePaymentMethod.mpesa,
        categoryId: stockCategory,
        note: 'Fruit and vegetables',
      );
    }

    // Customers who owe, and suppliers owed.
    _clock = eat(2026, 10, 19, 16, 10);
    await sales.sell(
      [SalePart(SalePaymentMethod.credit, kes(850))],
      credit: CreditTerms(
        customer: 'Peter Kamau',
        dueDate: CalendarDate(2026, 10, 26),
      ),
    );
    _clock = eat(2026, 10, 30, 11, 30);
    await sales.sell(
      [SalePart(SalePaymentMethod.credit, kes(760))],
      credit: CreditTerms(
        customer: 'Achieng Otieno',
        dueDate: CalendarDate(2026, 11, 6),
      ),
    );
    _clock = eat(2026, 11, 2, 10);
    await sales.sell(
      [SalePart(SalePaymentMethod.credit, kes(450))],
      credit: CreditTerms(
        customer: 'Grace Wanjiru',
        dueDate: CalendarDate(2026, 11, 9),
      ),
    );
    _clock = eat(2026, 11, 3, 7, 30);
    await sales.bought(
      amountMinor: kes(4500),
      method: SalePaymentMethod.credit,
      categoryId: stockCategory,
      supplier: 'Fresh Farm Supplies',
      dueDate: CalendarDate(2026, 11, 10),
      note: 'Tomatoes and onions',
    );

    // Today, Thursday 5 November.
    _clock = eat(2026, 11, 5, 7, 25);
    await sales.bought(
      amountMinor: kes(800),
      method: SalePaymentMethod.cash,
      categoryId: stockCategory,
      itemId: items['Tomatoes'],
      quantityMilli: 10000,
      note: 'Tomatoes',
    );
    _clock = eat(2026, 11, 5, 8, 10);
    await sales.sell(
      [SalePart(SalePaymentMethod.cash, kes(210))],
      lines: [
        line('Kale', 3, 30, unit: 'bunch'),
        line('Tomatoes', 1, 120, unit: 'kg'),
      ],
    );
    _clock = eat(2026, 11, 5, 8, 45);
    await sms(eat(2026, 11, 5, 8, 46), 580, 'PETER KAMAU', 'TK10000001');
    mpesaSaleId = (await sales.sell(
      [SalePart(SalePaymentMethod.mpesa, kes(580))],
      lines: [
        line('Eggs', 1, 450, unit: 'tray'),
        line('Milk', 2, 65, unit: 'packet'),
      ],
    )).saleId;
    _clock = eat(2026, 11, 5, 9, 30);
    await sales.bought(
      amountMinor: kes(660),
      method: SalePaymentMethod.credit,
      categoryId: stockCategory,
      supplier: 'Valley Dairy',
      dueDate: CalendarDate(2026, 11, 12),
      itemId: items['Milk'],
      quantityMilli: 12000,
      note: 'Milk',
    );
    _clock = eat(2026, 11, 5, 10, 15);
    await sales.sell(
      [SalePart(SalePaymentMethod.cash, kes(260))],
      lines: [
        line('Onions', 2, 100, unit: 'kg'),
        line('Cabbage', 1, 60),
      ],
    );
    _clock = eat(2026, 11, 5, 11, 20);
    await sales.sell(
      [SalePart(SalePaymentMethod.credit, kes(440))],
      credit: CreditTerms(
        customer: 'Achieng Otieno',
        dueDate: CalendarDate(2026, 11, 12),
      ),
      lines: [
        line('Tomatoes', 2, 120, unit: 'kg'),
        line('Onions', 1, 100, unit: 'kg'),
        line('Avocados', 4, 25),
      ],
    );
    _clock = eat(2026, 11, 5, 12, 5);
    await sms(eat(2026, 11, 5, 12, 6), 300, 'GRACE WANJIRU', 'TK10000002');
    await sales.sell(
      [
        SalePart(SalePaymentMethod.cash, kes(400)),
        SalePart(SalePaymentMethod.mpesa, kes(300)),
      ],
      lines: [
        line('Eggs', 1, 450, unit: 'tray'),
        line('Bananas', 1, 150, unit: 'bunch'),
        line('Delivery', 1, 100),
      ],
    );
    _clock = eat(2026, 11, 5, 14, 30);
    await sales.sell(
      [SalePart(SalePaymentMethod.mpesa, kes(300))],
      note: 'Avocados',
      lines: [line('Avocados', 12, 25)],
    );
    _clock = eat(2026, 11, 5, 15, 10);
    await sales.sell(
      [SalePart(SalePaymentMethod.cash, kes(180))],
      lines: [
        line('Kale', 2, 30, unit: 'bunch'),
        line('Tomatoes', 1, 120, unit: 'kg'),
      ],
    );
    _clock = eat(2026, 11, 5, 16);
    await sms(eat(2026, 11, 5, 16, 2), 250, 'MARY NJERI', 'TK10000003');
    _clock = eat(2026, 11, 5, 16, 45);
    await sales.sell(
      [SalePart(SalePaymentMethod.cash, kes(640))],
      lines: [
        line('Tomatoes', 2, 120, unit: 'kg'),
        line('Onions', 2, 100, unit: 'kg'),
        line('Cabbage', 2, 60),
      ],
    );
    _clock = eat(2026, 11, 5, 17, 5);
    await sms(eat(2026, 11, 5, 17, 6), 950, 'JOHN MWANGI', 'TK10000004');
    await sales.sell(
      [SalePart(SalePaymentMethod.mpesa, kes(950))],
      lines: [
        line('Eggs', 1, 450, unit: 'tray'),
        line('Bananas', 1, 150, unit: 'bunch'),
        line('Milk', 2, 65, unit: 'packet'),
        line('Kale', 4, 30, unit: 'bunch'),
        line('Delivery', 1, 100),
      ],
    );
    _clock = eat(2026, 11, 5, 17, 40);
  }
}

Future<_Shop> _open(WidgetTester tester) async {
  final db = openTestDatabase();
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => _clock),
      deviceRegionProvider.overrideWithValue('KE'),
      spacesProvider.overrideWith(_Spaces.new),
      activeSpaceProvider.overrideWithValue(_shop),
      ...appLockOverrides(),
    ],
  );
  addTearDown(c.dispose);
  final shop = _Shop(db, c);
  await tester.runAsync(shop.seed);
  return shop;
}

final _nav = GlobalKey<NavigatorState>();

Future<void> _pump(WidgetTester tester, _Shop shop, Widget home) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: shop.c,
      child: shotApp(home, navigatorKey: _nav),
    ),
  );
  await settleFrames(tester);
}

/// [body] in the business tab bar; over [root] when given.
Widget _tab(Widget body, int index, {Widget? root}) =>
    tabShell(body, tabs: businessTabs, index: index, root: root);

/// Opens [screen] over Today, as the app does, so it has a back arrow.
Future<void> _push(WidgetTester tester, _Shop shop, Widget screen) async {
  await _pump(tester, shop, _tab(const HomeScreen(), 0));
  // ignore: unawaited_futures
  _nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => screen));
  await settleFrames(tester);
}

void main() {
  screenshot('today', (tester) async {
    final shop = await _open(tester);
    await _pump(tester, shop, _tab(const HomeScreen(), 0));
    await snap(tester);
  });

  screenshot('money', (tester) async {
    final shop = await _open(tester);
    await _pump(tester, shop, _tab(const MoneyScreen(), 1));
    await snap(tester);
  });

  screenshot('people', (tester) async {
    final shop = await _open(tester);
    await _pump(tester, shop, _tab(const PeopleScreen(), 2));
    await snap(tester);
  });

  screenshot('stock', (tester) async {
    final shop = await _open(tester);
    await _pump(tester, shop, _tab(const StockScreen(), 3));
    await snap(tester);
  });

  // Sell with items picked, then the pay sheet with its way-to-pay menu.
  screenshot('sell', (tester) async {
    final shop = await _open(tester);
    await _push(tester, shop, const SellScreen());
    for (final name in [
      'Avocados',
      'Avocados',
      'Avocados',
      'Avocados',
      'Eggs',
      'Kale',
      'Kale',
    ]) {
      await tester.tap(find.text(name));
      await tester.pump();
    }
    await snap(tester);
    await tester.tap(find.byKey(const Key('sell-pay')));
    await settleFrames(tester);
    await tester.tap(find.byKey(const Key('pay-way')));
    await settleFrames(tester);
    await snap(tester, variant: 'pay');
  });

  screenshot('sell-keypad', (tester) async {
    final shop = await _open(tester);
    await _push(tester, shop, const AmountPadScreen());
    await tester.enterText(
      find.byKey(const Key('sell-note')),
      'Mixed vegetables',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    for (final k in ['3', '5', '0']) {
      await tester.tap(find.byKey(Key('sell-key-$k')));
      await tester.pump();
    }
    await snap(tester);
  });

  screenshot('receipt', (tester) async {
    final shop = await _open(tester);
    await _push(tester, shop, const SellScreen());
    final context = _nav.currentState!.overlay!.context;
    // ignore: unawaited_futures
    showReceiptSheet(context, shop.mpesaSaleId);
    await settleFrames(tester);
    await snap(tester);
  });

  screenshot('close-day', (tester) async {
    final shop = await _open(tester);
    await _push(tester, shop, const CloseDayScreen());
    final day = await tester.runAsync(
      () => shop.c.read(todayCashProvider.future),
    );
    await tester.enterText(
      find.byKey(const Key('close-counted')),
      '${day!.expectedMinor ~/ 100}',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await snap(tester);
  });

  screenshot('tax', (tester) async {
    final shop = await _open(tester);
    await _pump(
      tester,
      shop,
      _tab(const TaxScreen(), 4, root: const HomeScreen()),
    );
    await snap(tester);
  });
}
