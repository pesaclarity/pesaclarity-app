import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/security/data/key_vault.dart';
import 'package:pesaclarity/src/features/security/data/screen_capture_blocker.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/security/domain/lock_settings.dart';
import 'package:pesaclarity/src/features/security/presentation/security_settings_card.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';

const _title = 'Allow screenshots and screen recording';
const _blocked =
    "Blocked. Pesa Clarity's screen is also hidden in recent apps.";
const _allowed =
    'Screenshots, recordings and recent apps show your amounts. Tap the eye '
    'to hide them first.';

void main() {
  late MemorySecureStore store;
  late FakeScreenCaptureBlocker phone;

  setUp(() {
    store = MemorySecureStore();
    phone = FakeScreenCaptureBlocker();
  });

  /// The Security card on its own. [canBlock] says whether the phone lets
  /// the app block screenshots; left out, the platform decides.
  Future<void> pumpCard(WidgetTester tester, {bool? canBlock}) async {
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...appLockOverrides(store: store),
          screenCaptureBlockerProvider.overrideWithValue(phone),
          if (canBlock != null)
            canBlockScreenCaptureProvider.overrideWithValue(canBlock),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: const [SecuritySettingsCard()],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool switchedOn(WidgetTester tester) => tester
      .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, _title))
      .value;

  Object? saved() => switch (store.values[KeyVault.settingsName]) {
    final String raw =>
      (jsonDecode(raw) as Map<String, Object?>)['allowScreenCapture'],
    null => null,
  };

  testWidgets('on Android the row starts blocked, under the other switches', (
    tester,
  ) async {
    await pumpCard(tester, canBlock: true);

    expect(switchedOn(tester), isFalse);
    expect(find.text(_blocked), findsOneWidget);
    expect(find.text(_allowed), findsNothing);
    expect(phone.asked, isEmpty);

    // In the Security card, after Hide balances on open.
    expect(
      find.descendant(of: find.byType(Card), matching: find.text(_title)),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(find.text(_title)).dy,
      greaterThan(tester.getTopLeft(find.text('Hide balances on open')).dy),
    );
  });

  testWidgets('the switch allows them and blocks them again, at once', (
    tester,
  ) async {
    await pumpCard(tester, canBlock: true);

    await tester.tap(find.text(_title));
    await tester.pumpAndSettle();
    expect(switchedOn(tester), isTrue);
    expect(find.text(_allowed), findsOneWidget);
    expect(find.text(_blocked), findsNothing);
    expect(phone.asked, ['allow']);
    expect(saved(), isTrue);

    await tester.tap(find.text(_title));
    await tester.pumpAndSettle();
    expect(switchedOn(tester), isFalse);
    expect(find.text(_blocked), findsOneWidget);
    expect(find.text(_allowed), findsNothing);
    expect(phone.asked, ['allow', 'block']);
    expect(saved(), isFalse);
  });

  testWidgets('opens switched on when they were allowed before', (
    tester,
  ) async {
    await testKeyVault(store)
        .writeSettings(const LockSettings(allowScreenCapture: true));

    await pumpCard(tester, canBlock: true);

    expect(switchedOn(tester), isTrue);
    expect(find.text(_allowed), findsOneWidget);
    expect(phone.asked, ['allow']);
  });

  testWidgets('stays off when the phone does not allow them', (tester) async {
    phone.works = false;
    await pumpCard(tester, canBlock: true);

    await tester.tap(find.text(_title));
    await tester.pumpAndSettle();

    expect(switchedOn(tester), isFalse);
    expect(find.text(_blocked), findsOneWidget);
    expect(saved(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('iPhone has no such row', (tester) async {
    await pumpCard(tester, canBlock: false);

    expect(find.text(_title), findsNothing);
    expect(find.text(_blocked), findsNothing);
    expect(find.text(_allowed), findsNothing);
    // The rest of the card is there.
    expect(find.text('App lock'), findsOneWidget);
    expect(find.text('Hide balances on open'), findsOneWidget);
    expect(phone.asked, isEmpty);
  });

  testWidgets(
    'the platform decides: shown on Android, not on iPhone',
    (tester) async {
      await pumpCard(tester);

      final android = defaultTargetPlatform == TargetPlatform.android;
      expect(find.text(_title), android ? findsOneWidget : findsNothing);
      expect(find.text('Hide balances on open'), findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testAppWidgets('Profile has the switch, and it works there', (tester) async {
    await pumpApp(
      tester,
      db: openTestDatabase(),
      secureStore: store,
      overrides: [screenCaptureBlockerProvider.overrideWithValue(phone)],
    );
    await finishOnboarding(tester);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();

    await tapText(tester, _title);
    expect(switchedOn(tester), isTrue);
    expect(find.text(_allowed), findsOneWidget);
    expect(phone.asked, ['allow']);
    expect(saved(), isTrue);

    await tapText(tester, _title);
    expect(switchedOn(tester), isFalse);
    expect(find.text(_blocked), findsOneWidget);
    expect(phone.asked, ['allow', 'block']);
    expect(saved(), isFalse);
  });
}
