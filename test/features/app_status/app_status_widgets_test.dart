import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/features/app_status/domain/app_status.dart';
import 'package:pesaclarity/src/features/app_status/presentation/app_notice_cards.dart';
import 'package:pesaclarity/src/features/app_status/presentation/update_required_screen.dart';
import 'package:pesaclarity/src/features/home/application/cash_flow_forecast_provider.dart';
import 'package:pesaclarity/src/features/home/application/health_index_provider.dart';
import 'package:pesaclarity/src/features/home/application/safe_to_spend_provider.dart';
import 'package:pesaclarity/src/features/home/application/upcoming_bills_provider.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/features/income/application/income_providers.dart';
import 'package:pesaclarity/src/features/review/application/review_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/test_app.dart';
import 'app_status_fakes.dart';

void main() {
  late String publicKey;

  setUpAll(() async => publicKey = await publicKeyOf(testSeed));

  Future<FakeUpdateOpener> pump(
    WidgetTester tester, {
    required Object? response,
    required Widget Function() home,
    ThemeData? theme,
    AppFlavor flavor = AppFlavor.play,
    MemorySettings? settings,
    List<Override> extra = const [],
  }) async {
    final opener = FakeUpdateOpener();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...appStatusOverrides(
            source: FakeAppStatusSource(response),
            publicKey: publicKey,
            settings: settings ?? MemorySettings(),
            flavor: flavor,
            opener: opener,
          ),
          ...extra,
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          builder: (context, child) => UpdateRequiredGate(child: child!),
          home: home(),
        ),
      ),
    );
    await settleFrames(tester);
    return opener;
  }

  Widget homeCards() => const Scaffold(
    body: Padding(padding: EdgeInsets.all(20), child: AppNoticeCards()),
  );

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    testWidgets('update card in $name: Update opens the store', (tester) async {
      final opener = await pump(
        tester,
        theme: theme,
        response: await tester.runAsync(
          () => signed(payload(notices: [updateNotice()])),
        ),
        home: homeCards,
      );
      expect(find.text('Pesa Clarity 0.4.0 is ready'), findsOneWidget);
      expect(
        find.text('Reads Equity card payments and fixes Fuliza totals.'),
        findsOneWidget,
      );
      final card = tester.widget<Card>(
        find.byKey(const Key('app-notice-n-040')),
      );
      expect(card, isNotNull);
      await tester.tap(find.text('Update'));
      await tester.pump();
      expect(opener.opened.single.host, 'play.google.com');
      expect(tester.takeException(), isNull);
    });

    testWidgets('required screen in $name', (tester) async {
      await pump(
        tester,
        theme: theme,
        response: await tester.runAsync(
          () => signed(
            payload(
              notices: [
                updateNotice(
                  latest: '0.3.2',
                  min: '0.3.2',
                  reason: amountsWrongReason,
                  body:
                      'This version reads some M-PESA messages wrongly, so '
                      'your totals may be off.\n\nThe update fixes it, then '
                      'reads your messages again. Nothing on your phone is '
                      'lost.',
                ),
              ],
            ),
          ),
        ),
        home: () => const Scaffold(body: Text('The app')),
      );
      expect(find.text('Please update Pesa Clarity'), findsOneWidget);
      expect(find.textContaining('reads some M-PESA'), findsOneWidget);
      expect(find.textContaining('Nothing on your phone'), findsOneWidget);
      expect(find.text('Update now'), findsOneWidget);
      expect(
        find.text("You're on 0.3.0 · 0.3.2 or newer is needed"),
        findsOneWidget,
      );
      expect(find.text('The app'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('news has no button and closes', (tester) async {
    final settings = MemorySettings();
    await pump(
      tester,
      settings: settings,
      response: await tester.runAsync(
        () => signed(payload(notices: [infoNotice()])),
      ),
      home: homeCards,
    );
    expect(find.text('KCB changed its messages'), findsOneWidget);
    expect(find.text('Update'), findsNothing);
    await tester.tap(find.byTooltip('Close'));
    await settleFrames(tester);
    expect(find.text('KCB changed its messages'), findsNothing);
    expect(settings.values['app_status']!['dismissed'], ['info:n-kcb']);
  });

  testWidgets('back cannot close the required screen; Update now goes to '
      'F-Droid on the F-Droid build', (tester) async {
    final opener = await pump(
      tester,
      flavor: AppFlavor.foss,
      response: await tester.runAsync(
        () => signed(
          payload(
            build: 'foss',
            notices: [
              updateNotice(
                latest: '0.3.2',
                min: '0.3.2',
                reason: amountsWrongReason,
              ),
            ],
          ),
        ),
      ),
      home: () => const Scaffold(body: Text('The app')),
    );
    expect(find.byKey(const Key('update-required')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update-required')), findsOneWidget);
    await tester.tap(find.text('Update now'));
    await tester.pump();
    expect(
      opener.opened.single.toString(),
      'https://f-droid.org/packages/com.pesaclarity.app/',
    );
  });

  testWidgets('a minimum without amounts_wrong is only the card', (
    tester,
  ) async {
    await pump(
      tester,
      response: await tester.runAsync(
        () => signed(
          payload(
            notices: [updateNotice(latest: '0.3.2', min: '0.3.2')],
          ),
        ),
      ),
      home: homeCards,
    );
    expect(find.byKey(const Key('update-required')), findsNothing);
    expect(find.text('Update'), findsOneWidget);
  });

  testWidgets('offline: no card and no block', (tester) async {
    await pump(tester, response: null, home: homeCards);
    expect(find.byType(Card), findsNothing);
    expect(find.byKey(const Key('update-required')), findsNothing);
  });

  testWidgets('on Home the card sits under the lead card', (tester) async {
    final db = openTestDatabase();
    await pump(
      tester,
      response: await tester.runAsync(
        () => signed(payload(notices: [updateNotice()])),
      ),
      home: () => const HomeScreen(),
      extra: [
        appDatabaseProvider.overrideWithValue(db),
        pendingReviewProvider.overrideWith((ref) => Stream.value(const [])),
        safeToSpendTodayProvider.overrideWith((ref) async => null),
        untilNextMoneyProvider.overrideWith((ref) async => null),
        cashFlowForecastProvider.overrideWith((ref) async => null),
        healthIndexProvider.overrideWith((ref) async => null),
        upcomingBillsProvider.overrideWith((ref) async => []),
      ],
    );
    final lead = tester.getTopLeft(find.text('Safe to spend today'));
    final card = tester.getTopLeft(find.text('Pesa Clarity 0.4.0 is ready'));
    expect(card.dy, greaterThan(lead.dy));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  });
}
