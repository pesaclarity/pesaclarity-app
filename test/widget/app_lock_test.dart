import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/app.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/onboarding_repository.dart';
import 'package:pesaclarity/src/features/security/application/balance_visibility.dart';
import 'package:pesaclarity/src/features/security/data/key_vault.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/security/domain/lock_settings.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/shared/widgets/hero_figure_card.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/fake_app_lock.dart';
import '../helpers/fake_sms_source.dart';
import '../helpers/test_app.dart';

const _pin = '246810';
const _lockTitle = 'Enter your PIN';
const _homeQuestion = 'Safe to spend today';

void main() {
  late MemorySecureStore store;
  late AppDatabase db;
  late DateTime now;
  late bool databaseOpened;
  late FakeBiometricAuthenticator biometrics;

  setUp(() {
    store = MemorySecureStore();
    db = openTestDatabase();
    now = DateTime.utc(2026, 10, 26, 5);
    databaseOpened = false;
    biometrics = FakeBiometricAuthenticator();
  });

  /// Puts the phone in the state of someone who finished onboarding and set
  /// [_pin], with [settings] saved.
  Future<void> lockedInstall({
    LockSettings settings = const LockSettings(pinSet: true),
  }) async {
    await DriftOnboardingRepository(db).markComplete();
    final vault = testKeyVault(store);
    final key = await vault.readOrCreateOpenKey();
    await vault.setPin(_pin, key);
    if (settings.biometricEnabled) await vault.enableBiometric(key);
    await vault.writeSettings(settings);
  }

  Future<void> launch(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          ...appLockOverrides(store: store, biometrics: biometrics),
          clockProvider.overrideWithValue(() => now),
          appDatabaseProvider.overrideWith((ref) {
            databaseOpened = true;
            return db;
          }),
          smsSourceProvider.overrideWithValue(FakeSmsSource()),
        ],
        child: const PesaClarityApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterPin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.widgetWithText(TextButton, digit));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  /// Scrolls Profile until [text] shows, then taps it.
  Future<void> tapSetting(WidgetTester tester, String text) async {
    await tester.scrollUntilVisible(
      find.text(text),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> goToBackground(WidgetTester tester, Duration away) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    now = now.add(away);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  testAppWidgets('a fresh install goes straight to onboarding', (tester) async {
    await launch(tester);

    expect(find.text(_lockTitle), findsNothing);
    expect(find.text('Know what you can spend today.'), findsOneWidget);
    expect(store.values[KeyVault.plainKeyName], isNotNull);
  });

  testAppWidgets('keeps the database shut until the right PIN', (tester) async {
    await lockedInstall();
    await launch(tester);

    expect(find.text(_lockTitle), findsOneWidget);
    expect(find.text(_homeQuestion), findsNothing);
    expect(databaseOpened, isFalse);

    await enterPin(tester, '111111');
    expect(find.text('Wrong PIN. 3 tries left before a wait.'), findsOneWidget);
    expect(databaseOpened, isFalse);

    await enterPin(tester, _pin);
    expect(find.text(_lockTitle), findsNothing);
    expect(find.text(_homeQuestion), findsOneWidget);
    expect(databaseOpened, isTrue);
  });

  testAppWidgets('makes people wait after too many wrong PINs', (tester) async {
    await lockedInstall();
    await launch(tester);

    for (var i = 0; i < 5; i++) {
      await enterPin(tester, '111111');
    }
    expect(
      find.text('Too many wrong PINs. Try again in 0:30.'),
      findsOneWidget,
    );

    // Taps during the wait do nothing, even with the right PIN.
    await enterPin(tester, _pin);
    expect(find.text(_lockTitle), findsOneWidget);

    // The wait survives a restart.
    await launch(tester);
    expect(find.textContaining('Too many wrong PINs.'), findsOneWidget);

    now = now.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 1));
    await enterPin(tester, _pin);
    expect(find.text(_homeQuestion), findsOneWidget);
  });

  testAppWidgets('locks again after the grace period in the background', (
    tester,
  ) async {
    await lockedInstall();
    await launch(tester);
    await enterPin(tester, _pin);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();

    await goToBackground(tester, const Duration(seconds: 10));
    expect(find.text(_lockTitle), findsNothing);

    await goToBackground(tester, const Duration(seconds: 31));
    expect(find.text(_lockTitle), findsOneWidget);
    expect(find.text('Your account and settings'), findsNothing);

    await enterPin(tester, _pin);
    expect(find.text('Your account and settings'), findsOneWidget);
  });

  testAppWidgets('stays open in the background when no PIN is set', (
    tester,
  ) async {
    await pumpApp(tester, db: db, secureStore: store);
    await goToBackground(tester, const Duration(hours: 1));
    expect(find.text(_lockTitle), findsNothing);
  });

  testAppWidgets('unlocks with a fingerprint when it is on', (tester) async {
    biometrics.available = true;
    await lockedInstall(
      settings: const LockSettings(pinSet: true, biometricEnabled: true),
    );
    await launch(tester);

    expect(biometrics.prompts, 1);
    expect(find.text(_homeQuestion), findsOneWidget);
  });

  testAppWidgets('falls back to the PIN when the fingerprint is cancelled', (
    tester,
  ) async {
    biometrics
      ..available = true
      ..accept = false;
    await lockedInstall(
      settings: const LockSettings(pinSet: true, biometricEnabled: true),
    );
    await launch(tester);

    expect(find.text(_lockTitle), findsOneWidget);
    expect(find.byTooltip('Use fingerprint'), findsOneWidget);
    expect(databaseOpened, isFalse);
    await enterPin(tester, _pin);
    expect(find.text(_homeQuestion), findsOneWidget);
  });

  testAppWidgets('sets up app lock and fingerprint from Profile', (
    tester,
  ) async {
    biometrics.available = true;
    await pumpApp(tester, db: db, secureStore: store, biometrics: biometrics);
    await finishOnboarding(tester);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();

    await tapSetting(tester, 'App lock');
    expect(find.text('Choose a 6-digit PIN'), findsOneWidget);
    await enterPin(tester, _pin);
    expect(find.text('Enter the PIN again'), findsOneWidget);
    await enterPin(tester, '135790');
    expect(
      find.text('The PINs did not match. Choose a PIN again.'),
      findsOneWidget,
    );
    await enterPin(tester, _pin);
    await enterPin(tester, _pin);

    expect(find.text('App lock is on.'), findsOneWidget);
    expect(store.values[KeyVault.pinRecordName], isNotNull);
    expect(store.values[KeyVault.plainKeyName], isNull);

    await tapSetting(tester, 'Fingerprint unlock');
    expect(store.values[KeyVault.biometricKeyName], isNotNull);

    await tapSetting(tester, 'Lock after');
    await tester.tap(find.text('Immediately'));
    await tester.pumpAndSettle();
    await goToBackground(tester, const Duration(seconds: 1));
    // The fingerprint prompt unlocks straight away.
    expect(biometrics.prompts, 2);
    expect(find.text(_lockTitle), findsNothing);
    expect(find.text('Lock after'), findsOneWidget);

    await tapSetting(tester, 'App lock');
    expect(find.text('Enter your current PIN'), findsOneWidget);
    await enterPin(tester, _pin);
    expect(find.text('App lock is off.'), findsOneWidget);
    expect(store.values[KeyVault.pinRecordName], isNull);
    expect(store.values[KeyVault.biometricKeyName], isNull);
    expect(store.values[KeyVault.plainKeyName], isNotNull);
  });

  testAppWidgets('hides balances on open when asked', (tester) async {
    await lockedInstall(
      settings: const LockSettings(pinSet: true, hideBalancesOnOpen: true),
    );
    await launch(tester);
    await enterPin(tester, _pin);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PesaClarityApp)),
    );
    expect(container.read(balancesHiddenProvider), isTrue);
  });

  testWidgets('the hero card masks amounts and toggles them', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: HeroFigureCard(
              label: 'Safe to spend today',
              figure: 'KES 1,200',
              caption: 'Weekdays KES 950, weekends KES 1,500.',
            ),
          ),
        ),
      ),
    );

    expect(find.text('KES 1,200'), findsOneWidget);
    await tester.tap(find.byTooltip('Hide balances'));
    await tester.pump();
    expect(find.text('KES 1,200'), findsNothing);
    expect(find.text('KES •••••'), findsOneWidget);
    expect(
      find.text('Weekdays KES •••••, weekends KES •••••.'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Show balances'));
    await tester.pump();
    expect(find.text('KES 1,200'), findsOneWidget);
  });
}
