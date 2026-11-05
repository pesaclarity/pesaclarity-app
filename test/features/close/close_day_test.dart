import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/day_closes_repository.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space_categories.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/close/presentation/close_day_screen.dart';
import 'package:pesaclarity/src/features/people/application/people_providers.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late int cash;
  late int mpesa;
  final now = eat(2026, 11, 5, 19);

  setUp(() async {
    db = openTestDatabase();
    cash = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'Cash',
            type: AccountType.cash,
            openingDate: eat(2026, 11, 1, 0),
            openingBalanceMinor: const Value(100000),
          ),
        );
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

  Future<int> tx(int account, int amount, int hour, {bool inflow = true}) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: account,
          occurredAt: eat(2026, 11, 5, hour),
          amountMinor: amount,
          direction: inflow
              ? TransactionDirection.inflow
              : TransactionDirection.outflow,
          kind: const Value(TransactionKind.received),
          source: TransactionSource.sms,
          counterpartyName: const Value('Mary N.'),
        ),
      );

  test('the drawer: start, plus cash in, less cash out', () async {
    final c = container();
    await tx(cash, 80000, 10);
    await tx(cash, 25000, 11, inflow: false);
    final day = await c.read(todayCashProvider.future);
    expect(day.startMinor, 100000);
    expect(day.inMinor, 80000);
    expect(day.outMinor, 25000);
    expect(day.expectedMinor, 155000);
  });

  test('payments with no record can become a sale, a customer paying, '
      'or other income', () async {
    final c = container();
    final controller = c.read(salesControllerProvider);
    await controller.sell([
      const SalePart(SalePaymentMethod.credit, 50000),
    ], credit: const CreditTerms(customer: 'Otieno'));
    final a = await tx(mpesa, 35000, 16);
    final b = await tx(mpesa, 20000, 17);
    final d = await tx(mpesa, 30000, 12);
    final today = CalendarDate(2026, 11, 5);
    var open = await controller.unmatchedOn(today);
    expect(open.map((e) => e.id), [b, a, d]);

    await controller.saleFromPayment(open.firstWhere((e) => e.id == a));
    await controller.customerPaidBy(
      open.firstWhere((e) => e.id == b),
      'Otieno',
    );
    await controller.otherIncome(open.firstWhere((e) => e.id == d));
    open = await controller.unmatchedOn(today);
    expect(open, isEmpty);

    final otieno = (await c.read(customersProvider.future)).single;
    expect(otieno.owedMinor, 30000);
    final sales = await c.read(salesTodayProvider.future);
    expect(sales.day.byWay[SalePaymentMethod.mpesa], 35000);
    final other = await (db.select(
      db.transactions,
    )..where((t) => t.id.equals(d))).getSingle();
    final key = (await (db.select(
      db.categories,
    )..where((x) => x.id.equals(other.categoryOverrideId!))).getSingle()).key;
    expect(key, otherBusinessIncomeSeed.key);
  });

  testAppWidgets('closing books a difference only when asked', (tester) async {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    await tester.runAsync(() => tx(cash, 80000, 10));
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
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CloseDayScreen(),
                  ),
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
    expect(find.text('1,800'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('close-counted')), '1750');
    await tester.pump();
    expect(find.byKey(const Key('close-gap')), findsOneWidget);
    await tester.tap(find.byKey(const Key('close-book')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('close-day')));
    await settleFrames(tester);

    final close = await tester.runAsync(
      () => c.read(dayClosesRepositoryProvider).on(CalendarDate(2026, 11, 5)),
    );
    expect(close!.differenceMinor, -5000);
    final booked = await tester.runAsync(
      () =>
          (db.select(db.transactions)..where(
                (t) => t.direction.equalsValue(TransactionDirection.outflow),
              ))
              .getSingle(),
    );
    expect(booked!.amountMinor, 5000);
  });
}
