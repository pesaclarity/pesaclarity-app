import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/day_closes_repository.dart';
import 'package:pesaclarity/src/data/repositories/sales_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/business_day.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/close/application/business_day_providers.dart';
import 'package:pesaclarity/src/features/close/presentation/close_day_screen.dart';
import 'package:pesaclarity/src/features/profile/presentation/profile_screen.dart';
import 'package:pesaclarity/src/features/sales/application/sales_providers.dart';
import 'package:pesaclarity/src/features/security/application/device_integrity_providers.dart';
import 'package:pesaclarity/src/features/security/data/device_integrity_checker.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/security/domain/device_integrity.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/shared/format/date_labels.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/fake_app_lock.dart';
import '../../helpers/test_app.dart';

class _CleanPhone implements DeviceIntegrityChecker {
  const _CleanPhone();

  @override
  Future<DeviceIntegrityReport> check() async => DeviceIntegrityReport.clean;
}

void main() {
  setUp(() => UserTimeZone.set(nairobiUtcOffset));
  tearDown(UserTimeZone.resetToDevice);

  group('BusinessDay', () {
    const late = BusinessDay(endsAtHour: 6);

    test('a moment before the end counts on the day before', () {
      expect(late.dayOf(eat(2026, 11, 6, 1)), CalendarDate(2026, 11, 5));
      expect(late.dayOf(eat(2026, 11, 6, 6)), CalendarDate(2026, 11, 6));
      expect(
        BusinessDay.midnight.dayOf(eat(2026, 11, 6, 1)),
        CalendarDate(2026, 11, 6),
      );
    });

    test('the day runs from its end hour to the next', () {
      final day = CalendarDate(2026, 11, 5);
      expect(late.startOf(day), eat(2026, 11, 5, 6));
      expect(late.endOf(day), eat(2026, 11, 6, 6));
      expect(late.contains(day, eat(2026, 11, 6, 5, 59)), isTrue);
      expect(late.contains(day, eat(2026, 11, 6, 6)), isFalse);
      expect(late.contains(day, eat(2026, 11, 5, 5, 59)), isFalse);
    });

    test('keeps, and anything unknown means midnight', () {
      expect(BusinessDay.fromJson(late.toJson()), late);
      expect(BusinessDay.fromJson(null), BusinessDay.midnight);
      expect(BusinessDay.fromJson({'endsAtHour': 5}), BusinessDay.midnight);
      expect(BusinessDay.fromJson({'endsAtHour': '6'}), BusinessDay.midnight);
      expect(late.endLabel, '6 am');
      expect(BusinessDay.midnight.endLabel, 'Midnight');
    });
  });

  group('A day that ends at 6 am', () {
    late AppDatabase db;
    late int cash;
    final now = eat(2026, 11, 6, 2);

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
      await DriftAppSettingsRepository(db).writeJson(
        BusinessDayController.settingsKey,
        const BusinessDay(endsAtHour: 6).toJson(),
      );
    });

    List<Override> overrides() => [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => now),
    ];

    Future<void> cashIn(int amount, DateTime at) => db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            accountId: cash,
            occurredAt: at,
            amountMinor: amount,
            direction: TransactionDirection.inflow,
            kind: const Value(TransactionKind.received),
            source: TransactionSource.manual,
          ),
        );

    test(
      'sales and the drawer after midnight stay on the night before',
      () async {
        final c = ProviderContainer(overrides: overrides());
        addTearDown(c.dispose);
        await cashIn(10000, eat(2026, 11, 5, 5));
        await cashIn(20000, eat(2026, 11, 5, 22));
        await cashIn(30000, eat(2026, 11, 6, 1));

        expect(
          await c.read(businessTodayProvider.future),
          CalendarDate(2026, 11, 5),
        );
        final drawer = await c.read(todayCashProvider.future);
        // The 5 am cash belongs to the 4th's night.
        expect(drawer.startMinor, 110000);
        expect(drawer.inMinor, 50000);

        final controller = c.read(salesControllerProvider);
        await controller.sell([const SalePart(SalePaymentMethod.cash, 15000)]);
        final sales = await c.read(salesTodayProvider.future);
        expect(sales.day.date, CalendarDate(2026, 11, 5));
        expect(sales.day.byWay[SalePaymentMethod.cash], 15000);
      },
    );

    testAppWidgets('closing at 2 am closes the night before', (tester) async {
      final c = ProviderContainer(overrides: overrides());
      addTearDown(c.dispose);
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
      expect(
        find.text(
          '${longDate(CalendarDate(2026, 11, 5))} · business day until 6 am',
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byKey(const Key('close-counted')), '1000');
      await tester.pump();
      await tester.tap(find.byKey(const Key('close-day')));
      await settleFrames(tester);

      final closes = await tester.runAsync(
        () => c
            .read(dayClosesRepositoryProvider)
            .since(CalendarDate(2026, 11, 1)),
      );
      expect(closes!.single.day, CalendarDate(2026, 11, 5));
    });
  });

  testAppWidgets('Profile: a business chooses when its day ends', (
    tester,
  ) async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          ...appLockOverrides(store: MemorySecureStore()),
          deviceIntegrityCheckerProvider.overrideWithValue(const _CleanPhone()),
          activeSpaceProvider.overrideWithValue(
            const Space(
              id: 'abc123',
              name: 'Corner bar',
              kind: SpaceKind.business,
            ),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
      ),
    );
    await settleFrames(tester);
    await scrollTo(tester, find.byKey(const Key('profile-day-ends')));
    expect(find.text('Midnight'), findsOneWidget);
    await tester.tap(find.text('Midnight'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('day-ends-6')));
    await settleFrames(tester);
    expect(find.text('6 am'), findsOneWidget);
    final saved = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db)
              .readJson(BusinessDayController.settingsKey),
    );
    expect(BusinessDay.fromJson(saved), const BusinessDay(endsAtHour: 6));
  });
}
