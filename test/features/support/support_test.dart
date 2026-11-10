import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/features/home/application/cash_flow_forecast_provider.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';
import 'package:pesaclarity/src/features/home/application/upcoming_bills_provider.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';
import 'package:pesaclarity/src/features/review/application/review_providers.dart';
import 'package:pesaclarity/src/features/support/application/support_providers.dart';
import 'package:pesaclarity/src/features/support/domain/support.dart';
import 'package:pesaclarity/src/features/support/presentation/support_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/test_app.dart';

/// Saturday 14 November 2026, 09:00 EAT.
final _now = DateTime.utc(2026, 11, 14, 6);

const _defines = (
  url: 'https://pay.example.org/pay/@test?amount={amount}',
  payees: 'Test Payee',
  costs: 'https://example.org/sponsor/',
);

class _Opener implements SupportOpener {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

Future<int> _account(AppDatabase db) => db
    .into(db.accounts)
    .insert(
      AccountsCompanion.insert(
        name: 'M-Pesa',
        type: AccountType.mpesa,
        openingDate: DateTime.utc(2026),
      ),
    );

Future<void> _pay(
  AppDatabase db,
  int account, {
  required String to,
  required int amountMinor,
  required DateTime at,
  String? code,
}) => db
    .into(db.transactions)
    .insert(
      TransactionsCompanion.insert(
        accountId: account,
        occurredAt: at,
        amountMinor: amountMinor,
        direction: TransactionDirection.outflow,
        source: TransactionSource.sms,
        counterpartyName: Value(to),
        receiptNo: Value(code),
      ),
    );

Future<void> _remember(AppDatabase db, SupportState state) =>
    DriftAppSettingsRepository(db)
        .writeJson(SupportStateController.settingsKey, state.toJson());

List<Override> _overrides(
  AppDatabase db, {
  AppFlavor flavor = AppFlavor.foss,
  _Opener? opener,
}) => [
  appDatabaseProvider.overrideWithValue(db),
  clockProvider.overrideWithValue(() => _now),
  appFlavorProvider.overrideWithValue(flavor),
  supportDefinesProvider.overrideWithValue(_defines),
  if (opener != null) supportOpenerProvider.overrideWithValue(opener),
];

Future<void> _home(WidgetTester tester, List<Override> overrides) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overrides,
        pendingReviewProvider.overrideWith((ref) => Stream.value(const [])),
        safeToSpendTodayProvider.overrideWith((ref) async => null),
        untilNextMoneyProvider.overrideWith((ref) async => null),
        cashFlowForecastProvider.overrideWith((ref) async => null),
        healthIndexProvider.overrideWith((ref) async => null),
        upcomingBillsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
    ),
  );
  await settleFrames(tester);
}

void main() {
  test('only the F-Droid build has giving in the app', () {
    for (final flavor in AppFlavor.values) {
      final container = ProviderContainer(
        overrides: [
          appFlavorProvider.overrideWithValue(flavor),
          supportDefinesProvider.overrideWithValue(_defines),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(supportConfigProvider) != null,
        flavor == AppFlavor.foss,
        reason: flavor.name,
      );
    }
  });

  testAppWidgets('gifts are read from their own M-Pesa messages', (
    tester,
  ) async {
    final db = openTestDatabase();
    final container = ProviderContainer(overrides: _overrides(db));
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      final account = await _account(db);
      await _pay(
        db,
        account,
        to: 'TEST PAYEE',
        amountMinor: 20000,
        at: _now.subtract(const Duration(hours: 2)),
        code: 'TK10000001',
      );
      await _pay(
        db,
        account,
        to: 'Green Basket Grocers',
        amountMinor: 144000,
        at: _now.subtract(const Duration(hours: 1)),
      );
      final sub = container.listen(giftsProvider, (_, _) {});
      addTearDown(sub.close);
      final gifts = await container.read(giftsProvider.future);
      expect(gifts, hasLength(1));
      expect(gifts.single.amountMinor, 20000);
      expect(gifts.single.code, 'TK10000001');
    });
  });

  testAppWidgets('Home asks after 30 days, under the red card', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(
      () => _remember(
        db,
        SupportState(firstSeenAt: _now.subtract(const Duration(days: 40))),
      ),
    );
    await _home(tester, _overrides(db));
    expect(find.byKey(const Key('home-support')), findsOneWidget);
    expect(find.text('Pesa Clarity is free'), findsOneWidget);
    expect(
      find.text('No ads, no investors. If it helps you, buy us a coffee.'),
      findsOneWidget,
    );

    // The showing has started, so it rests 60 days from now.
    final saved = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db)
              .readJson(SupportStateController.settingsKey),
    );
    final state = SupportState.fromJson(saved);
    expect(state.showingSince, _now);
    expect(state.restUntil, _now.add(supportRestFor));
  });

  testAppWidgets('Home never asks in the first 30 days, or on Play', (
    tester,
  ) async {
    final db = openTestDatabase();
    await _home(tester, _overrides(db));
    expect(find.byKey(const Key('home-support')), findsNothing);

    final other = openTestDatabase();
    await tester.runAsync(
      () => _remember(
        other,
        SupportState(firstSeenAt: _now.subtract(const Duration(days: 40))),
      ),
    );
    await _home(tester, _overrides(other, flavor: AppFlavor.play));
    expect(find.byKey(const Key('home-support')), findsNothing);
  });

  testAppWidgets('a gift is thanked once, and Home stops asking', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() async {
      await _remember(
        db,
        SupportState(firstSeenAt: _now.subtract(const Duration(days: 40))),
      );
      await _pay(
        db,
        await _account(db),
        to: 'Test Payee',
        amountMinor: 20000,
        at: _now.subtract(const Duration(minutes: 5)),
        code: 'TK10000001',
      );
    });
    await _home(tester, _overrides(db));
    await tester.pumpAndSettle();
    expect(find.text('Thank you'), findsOneWidget);
    expect(find.textContaining('Your 200 reached us.'), findsOneWidget);
    expect(find.text('Today · TK10000001'), findsOneWidget);
    expect(
      find.text(
        'No goods or services were given in return. Kept on this phone only.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('home-support')), findsNothing);

    await tester.tap(find.byKey(const Key('support-thanks-done')));
    await tester.pumpAndSettle();
    expect(find.text('Thank you'), findsNothing);

    // Once is enough.
    await _home(tester, _overrides(db));
    await tester.pumpAndSettle();
    expect(find.text('Thank you'), findsNothing);
  });

  testAppWidgets('Support gives the chosen amount by M-Pesa', (tester) async {
    final db = openTestDatabase();
    final opener = _Opener();
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(db, opener: opener),
        child: MaterialApp(theme: AppTheme.light, home: const SupportScreen()),
      ),
    );
    await settleFrames(tester);

    expect(find.text('Free, and it stays free'), findsOneWidget);
    expect(
      find.text(
        'Giving never unlocks anything. Every feature is free for everyone.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('support-give')));
    await tester.pump();
    expect(opener.opened.last.toString(), endsWith('?amount=200'));

    await tester.tap(find.byKey(const Key('support-amount')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('support-amount-500')));
    await tester.pumpAndSettle();
    expect(find.text('Give 500 with M-Pesa'), findsOneWidget);

    await tester.tap(find.byKey(const Key('support-amount')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('support-amount-other')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('support-give')))
          .onPressed,
      isNull,
      reason: 'waits for an amount',
    );
    await tester.enterText(find.byKey(const Key('support-other')), '350');
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('support-give')));
    await tester.tap(find.byKey(const Key('support-give')));
    await tester.pump();
    expect(opener.opened.last.toString(), endsWith('?amount=350'));

    await tester.ensureVisible(find.byKey(const Key('support-costs')));
    await tester.tap(find.byKey(const Key('support-costs')));
    await tester.pump();
    expect(opener.opened.last.toString(), 'https://example.org/sponsor/');

    await tester.ensureVisible(find.byKey(const Key('support-dont-ask')));
    await tester.tap(find.byKey(const Key('support-dont-ask')));
    await settleFrames(tester);
    final saved = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db)
              .readJson(SupportStateController.settingsKey),
    );
    expect(SupportState.fromJson(saved).optedOut, isTrue);
  });
}
