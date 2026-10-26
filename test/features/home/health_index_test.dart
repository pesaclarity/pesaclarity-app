import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/health/health_index.dart';
import 'package:pesaclarity/src/domain/health/health_inputs.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

void main() {
  group('healthIndexProvider', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // Monday 26 October 2026, 08:00 EAT: September is the last full month.
          clockProvider.overrideWithValue(() => DateTime.utc(2026, 10, 26, 5)),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<int> account(AccountType type, {int opening = 0}) => db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: type.name,
            type: type,
            openingBalanceMinor: Value(opening),
            openingDate: DateTime.utc(2026),
          ),
        );

    Future<void> income(int accountId, DateTime at, int amount) async {
      final salary = await db
          .into(db.categories)
          .insertOnConflictUpdate(
            CategoriesCompanion.insert(
              id: const Value(1),
              name: 'Salary',
              type: CategoryType.income,
            ),
          );
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              accountId: accountId,
              occurredAt: at,
              amountMinor: amount,
              direction: TransactionDirection.inflow,
              categoryOverrideId: Value(salary),
              source: TransactionSource.manual,
            ),
          );
    }

    test('is null when last month has no transactions', () async {
      expect(await container.read(healthIndexProvider.future), isNull);
    });

    test('scores last month with the savings balance at its end', () async {
      final mpesa = await account(AccountType.mpesa);
      await account(AccountType.sacco, opening: 3000000);
      await income(mpesa, DateTime.utc(2026, 9, 25, 9), 10000000);

      final result = await container.read(healthIndexProvider.future);
      expect(result, isNotNull);
      expect(result!.index.month, YearMonth(2026, 9));
      expect(result.index.inputs.incomeMinor, 10000000);
      expect(result.index.inputs.savingsBalanceMinor, 3000000);
      expect(result.change, isNull);
    });

    test('reports the change on the month before', () async {
      final mpesa = await account(AccountType.mpesa);
      await income(mpesa, DateTime.utc(2026, 8, 25, 9), 10000000);
      await income(mpesa, DateTime.utc(2026, 9, 25, 9), 10000000);

      final result = await container.read(healthIndexProvider.future);
      expect(result!.change, 0);
    });
  });

  testWidgets('Home shows the score, band and change', (tester) async {
    final index = HealthIndex.compute(HealthInputs(month: YearMonth(2026, 9)));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          safeToSpendTodayProvider.overrideWith((ref) async => null),
          healthIndexProvider.overrideWith(
            (ref) async => HealthOnHome(index, 3),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Financial Health Index'), findsOneWidget);
    expect(find.text('63'), findsOneWidget);
    expect(find.text('Coping. Up 3 on the month before.'), findsOneWidget);
  });
}
