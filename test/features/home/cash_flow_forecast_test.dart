import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/features/home/application/cash_flow_forecast_provider.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';
import 'package:pesaclarity/src/features/home/application/upcoming_bills_provider.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/features/review/application/review_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // Monday 26 October 2026, 08:00 EAT.
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 26, 5)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<int> account(AccountType type, int opening) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: type.name,
          type: type,
          openingBalanceMinor: Value(opening),
          openingDate: DateTime.utc(2026, 9),
        ),
      );

  Future<void> seed() async {
    final mpesa = await account(AccountType.mpesa, 1000000);
    await account(AccountType.sacco, 5000000);
    final rent = await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(name: 'Rent', type: CategoryType.expense),
        );
    await db
        .into(db.recurring)
        .insert(
          RecurringCompanion.insert(
            name: 'Rent',
            categoryId: Value(rent),
            amountMinor: 600000,
            frequency: RecurrenceFrequency.monthly,
            startDate: DateTime.utc(2026, 1, 28),
          ),
        );
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: mpesa,
            occurredAt: DateTime.utc(2026, 10, 20, 9),
            amountMinor: 400000,
            direction: TransactionDirection.outflow,
            source: TransactionSource.manual,
          ),
        );
  }

  test('is null without day-to-day accounts', () async {
    await account(AccountType.sacco, 100);
    expect(await container.read(cashFlowForecastProvider.future), isNull);
  });

  test('forecasts day-to-day accounts against this month\'s plan', () async {
    await seed();
    final result = await container.read(cashFlowForecastProvider.future);
    expect(result, isNotNull);
    expect(result!.startingBalanceMinor, 600000);
    expect(result.pace.weekdayMinor, 20000);
    expect(result.messages, [
      'At this pace you hit zero on the 28th.',
      'Your Rent payment of KES 6,000 on the 28th may not go through. '
          'You would be KES 400 short.',
    ]);
  });

  testWidgets('Home shows the forecast', (tester) async {
    await tester.runAsync(seed);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: ProviderContainer(
          parent: container,
          overrides: [
            pendingReviewProvider.overrideWith((ref) => Stream.value(const [])),
            safeToSpendTodayProvider.overrideWith((ref) async => null),
            healthIndexProvider.overrideWith((ref) async => null),
            upcomingBillsProvider.overrideWith((ref) async => []),
          ],
        ),
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.runAsync(
      () => container.read(cashFlowForecastProvider.future),
    );
    await tester.pumpAndSettle();

    expect(find.text('At this pace you hit zero on the 28th.'), findsOneWidget);
  });
}
