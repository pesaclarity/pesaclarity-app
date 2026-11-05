import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/category_seeds.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/data/repositories/tax_repository.dart';
import 'package:pesaclarity/src/domain/books/book_account.dart';
import 'package:pesaclarity/src/domain/sales/sale_matching.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/spaces/space_categories.dart';
import 'package:pesaclarity/src/domain/tax/tax_estimate.dart';
import 'package:pesaclarity/src/features/books/application/books_providers.dart';
import 'package:pesaclarity/src/features/people/application/people_providers.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/sales/presentation/choose_payments_sheet.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/tax/application/tax_providers.dart';
import 'package:pesaclarity/src/features/tax/presentation/tax_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  late int mpesa;
  final now = eat(2026, 11, 30, 14);

  setUp(() async {
    db = openTestDatabase();
    mpesa = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: eat(2026, 1, 1, 0),
          ),
        );
  });

  List<Override> overrides() => [
    appDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => now),
    activeSpaceProvider.overrideWithValue(
      const Space(
        id: 'amina',
        name: 'Amina Consulting',
        kind: SpaceKind.business,
      ),
    ),
  ];

  ProviderContainer container() {
    final c = ProviderContainer(overrides: overrides());
    addTearDown(c.dispose);
    return c;
  }

  Future<int> message(
    int amount, {
    String name = 'Juhudi Sacco',
    bool inflow = true,
    int? category,
    DateTime? at,
  }) => db
      .into(db.transactions)
      .insert(
        TransactionsCompanion.insert(
          accountId: mpesa,
          occurredAt: at ?? now.add(const Duration(minutes: 1)),
          amountMinor: amount,
          direction: inflow
              ? TransactionDirection.inflow
              : TransactionDirection.outflow,
          kind: Value(
            inflow ? TransactionKind.received : TransactionKind.paybill,
          ),
          source: TransactionSource.sms,
          counterpartyName: Value(name),
          categoryOverrideId: Value(category),
        ),
      );

  Future<void> services(ProviderContainer c) => c
      .read(appSettingsRepositoryProvider)
      .writeJson('business.setup', {'sells': 'services'});

  /// Fees from a client, filed as sales.
  Future<int> fees(int amount, DateTime at) async => message(
    amount,
    name: 'Bidii Traders Ltd',
    category: await ensureCategory(db, salesSeed),
    at: at,
  );

  test('a client who kept back 5% pays the sale in full, as tax', () async {
    final c = container();
    final sale = await c.read(salesControllerProvider).sell([
      const SalePart(SalePaymentMethod.mpesa, 4000000),
    ]);
    await message(3800000);
    final controller = c.read(salesControllerProvider);
    final w = sale.waiting.single;
    await controller.settle(
      w,
      await controller.candidatesFor(w),
      short: ShortBy.taxWithheld,
      certificate: 'WHT-001',
    );
    expect((await db.select(db.sales).get()).single.totalMinor, 4000000);
    final withheld = (await c.read(taxRepositoryProvider).withheld()).single;
    expect(withheld.person, 'Juhudi Sacco');
    expect(withheld.amountMinor, 200000);
    expect(withheld.certificate, 'WHT-001');

    final books = await c.read(booksProvider.future);
    expect(books.unbalanced, isEmpty);
    expect(books.balanceOf(BookAccount.tax, currency: 'KES'), 200000);
    expect(books.balanceOf(BookAccount.owedToYou, currency: 'KES'), 0);
    final customers = await c.read(customersProvider.future);
    expect(customers.where((x) => x.owedMinor > 0), isEmpty);
  });

  test('the estimate: fees, costs, withheld and paid to KRA', () async {
    final c = container();
    await services(c);
    final tax = (await (db.select(
      db.categories,
    )..where((x) => x.key.equals('tax'))).getSingle()).id;
    await fees(12600000, eat(2026, 3, 2, 9));
    final software = await (db.select(
      db.categories,
    )..where((x) => x.type.equalsValue(CategoryType.expense))).get();
    await message(
      2480000,
      inflow: false,
      name: 'Software',
      category: software.first.id,
      at: eat(2026, 4, 2, 9),
    );
    await message(
      1074000,
      inflow: false,
      name: 'KRA',
      category: tax,
      at: eat(2026, 6, 18, 9),
    );
    await c
        .read(taxRepositoryProvider)
        .withhold(person: 'Juhudi Sacco', amountMinor: 630000, at: now);

    final view = await c.read(taxViewProvider.future);
    expect(view.kind, TaxKind.incomeTax);
    final f = view.income.figures;
    expect(f.incomeMinor, 12600000);
    expect(f.costsMinor, 2480000);
    expect(f.paidToKraMinor, 1074000);
    expect(f.withheldMinor, 630000);
    // 101,200 profit is below the first band once relief is taken off.
    expect(view.income.taxMinor, 0);
    expect(view.certificatesToCollect, ['Juhudi Sacco']);
  });

  testAppWidgets('the Tax screen shows the estimate and its settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = container();
    await tester.runAsync(() async {
      await services(c);
      await fees(126000000, eat(2026, 3, 2, 9));
      await c
          .read(taxRepositoryProvider)
          .withhold(person: 'Juhudi Sacco', amountMinor: 6300000, at: now);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: AppTheme.light, home: const TaxScreen()),
      ),
    );
    await settleFrames(tester);
    expect(find.text('Tax you may still owe for 2026'), findsOneWidget);
    expect(find.text('Fees earned'), findsOneWidget);
    expect(find.text('Jan to Nov'), findsOneWidget);
    // 1,260,000: 28,800 + 25,000 + 261,600, less 28,800 relief.
    expect(find.text('286,600'), findsOneWidget);
    expect(find.text('1 payment · 1 certificate to collect'), findsOneWidget);
    expect(
      find.textContaining('Collect certificates from Juhudi Sacco'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Next instalment is due 20 Dec'),
      findsOneWidget,
    );
    expect(find.textContaining('rules as of'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tax-file-as')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('file-as-Company')));
    await settleFrames(tester);
    expect(find.text('Company'), findsOneWidget);
    expect(find.text('378,000'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tax-withheld')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Juhudi Sacco · 63,000'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('certificate-number')),
      'WHT-77',
    );
    await tester.tap(find.byKey(const Key('certificate-save')));
    await settleFrames(tester);
    final w = await tester.runAsync(
      () => c.read(taxRepositoryProvider).withheld(),
    );
    expect(w!.single.certificate, 'WHT-77');
  });

  testAppWidgets('paid 5% less: Tax withheld is offered first', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = container();
    final w = await tester.runAsync(() async {
      final sale = await c.read(salesControllerProvider).sell([
        const SalePart(SalePaymentMethod.mpesa, 4000000),
      ]);
      await message(3800000);
      return sale.waiting.single;
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
    await tester.tap(find.byType(CheckboxListTile).first);
    await settleFrames(tester);
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const Key('short-taxWithheld')),
    );
    expect(chip.selected, isTrue);
    expect(find.text('Tax withheld (5%)'), findsOneWidget);
    expect(find.byKey(const Key('choose-tax-note')), findsOneWidget);
    expect(
      find.text('Expect 5% from Juhudi Sacco from now on'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('choose-save')));
    await settleFrames(tester);
    final withheld = await tester.runAsync(
      () => c.read(taxRepositoryProvider).withheld(),
    );
    expect(withheld!.single.amountMinor, 200000);
    final expected = await tester.runAsync(
      () => c.read(withholdingClientsProvider.future),
    );
    expect(expected, contains('juhudi sacco'));
  });
}
