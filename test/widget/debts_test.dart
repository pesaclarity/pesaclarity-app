import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/debts/payoff_order.dart';
import 'package:pesaclarity/src/features/debts/application/debts_overview_provider.dart';
import 'package:pesaclarity/src/features/debts/presentation/debts_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/goals_harness.dart' show settle;

/// 26 October 2026, 08:00 EAT.
final _now = DateTime.utc(2026, 10, 26, 5);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> addDebt(
    String lender,
    int balanceMajor, {
    int minimumMajor = 0,
    int rateBasisPoints = 0,
    DebtType type = DebtType.bankLoan,
  }) => db
      .into(db.debts)
      .insert(
        DebtsCompanion.insert(
          lender: lender,
          type: type,
          startingBalanceMinor: balanceMajor * 100,
          minimumPaymentMinor: Value(minimumMajor * 100),
          annualRateBasisPoints: Value(
            rateBasisPoints == 0 ? null : rateBasisPoints,
          ),
          isFormal: Value(type != DebtType.family),
        ),
      );

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => _now),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light, home: const DebtsScreen()),
      ),
    );
    await settle(tester);
    return container;
  }

  double topOf(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('starts with a way to add the first debt', (tester) async {
    await pump(tester);
    expect(find.text('Debt-free by'), findsOneWidget);
    expect(find.text('Remaining'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Add a debt'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Lender'),
      'Test Bank',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Owed now'),
      '12,000',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Interest a year'),
      '12.5',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Minimum each month'),
      '2,000',
    );
    await tester.tap(find.text('Add debt'));
    await settle(tester);

    expect(find.text('Remaining'), findsOneWidget);
    expect(find.text('KES 12,000'), findsOneWidget);
    expect(find.text('Test Bank'), findsOneWidget);
    expect(find.textContaining('12.5% p.a.'), findsOneWidget);
    expect(find.textContaining('Debt-free'), findsWidgets);
  });

  testWidgets('orders by strategy and keeps the choice', (tester) async {
    await addDebt('Small Loan', 3000, minimumMajor: 500, rateBasisPoints: 900);
    await addDebt(
      'Dear Card',
      20000,
      minimumMajor: 1500,
      rateBasisPoints: 3000,
    );
    final container = await pump(tester);

    // Avalanche: highest rate first.
    expect(topOf(tester, 'Dear Card'), lessThan(topOf(tester, 'Small Loan')));

    await tester.tap(find.text('Snowball'));
    await settle(tester);
    expect(topOf(tester, 'Small Loan'), lessThan(topOf(tester, 'Dear Card')));
    expect(
      (await container.read(debtPreferenceProvider.future)).strategy,
      PayoffStrategy.snowball,
    );
  });

  testWidgets('shows how extra a month brings the date closer', (tester) async {
    await addDebt(
      'Test Bank',
      40000,
      minimumMajor: 2000,
      rateBasisPoints: 1300,
    );
    await pump(tester);
    expect(
      find.text('Slide to see how much sooner you could be debt-free.'),
      findsOneWidget,
    );

    await tester.drag(find.byType(Slider), const Offset(300, 0));
    await settle(tester);
    expect(find.textContaining('sooner'), findsOneWidget);
    expect(find.textContaining('less interest'), findsOneWidget);
  });

  testWidgets('records a payment made by hand', (tester) async {
    await addDebt('Mama', 5000, type: DebtType.family);
    await pump(tester);
    expect(find.textContaining('Interest-free'), findsOneWidget);

    await tester.tap(find.text('Mama'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Payment'),
      '1,500',
    );
    await tester.tap(find.text('Record payment'));
    await settle(tester);

    expect(find.text('KES 3,500'), findsOneWidget);
  });

  testWidgets('removes a debt after asking', (tester) async {
    await addDebt('Test Bank', 1000, minimumMajor: 100);
    await pump(tester);

    await tester.tap(find.text('Test Bank'));
    await settle(tester);
    await tester.ensureVisible(find.text('Remove this debt'));
    await tester.tap(find.text('Remove this debt'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await settle(tester);

    expect(find.text('Test Bank'), findsNothing);
    expect(find.text('Debt-free by'), findsOneWidget);
  });
}
