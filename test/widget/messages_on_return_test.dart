import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/data/repositories/onboarding_repository.dart';
import 'package:pesaclarity/src/data/repositories/sms_scan_marks_repository.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/security/domain/lock_settings.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_scan_service.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';

import '../helpers/fake_app_lock.dart';
import '../helpers/fake_sms_source.dart';
import '../helpers/sms_samples.dart';
import '../helpers/test_app.dart';

const _lockTitle = 'Enter your PIN';
const _pin = '246810';

/// Who the till payment's message paid, as its row in Activity names them.
const _payee = 'EXAMPLE GROCERS';

void main() {
  late AppDatabase db;
  late FakeSmsSource sms;
  late MemorySecureStore store;

  /// Monday 26 October 2026, 18:00 EAT, when the app is opened. Each scan
  /// starts at [now], and the next one reads from then on.
  late DateTime now;

  setUp(() {
    db = openTestDatabase();
    sms = FakeSmsSource();
    addTearDown(sms.close);
    store = MemorySecureStore();
    now = DateTime.utc(2026, 10, 26, 15);
  });

  Future<void> launch(WidgetTester tester) => pumpApp(
    tester,
    db: db,
    sms: sms,
    secureStore: store,
    overrides: [
      clockProvider.overrideWithValue(() => now),
      smsScanServiceProvider.overrideWith(
        (ref) => SmsScanService(
          source: ref.watch(smsSourceProvider),
          ingestor: ref.watch(smsIngestorProvider),
          marks: ref.watch(smsScanMarksRepositoryProvider),
          clock: () => now,
        ),
      ),
    ],
  );

  Future<void> openActivity(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(PillNavigationBar),
        matching: find.text('Activity'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_payee), findsNothing);
  }

  /// Puts the app in the background for half an hour, with [meanwhile]
  /// happening there, then brings it back to the front.
  Future<void> leaveAndReturn(
    WidgetTester tester, {
    required void Function() meanwhile,
  }) async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    now = now.add(const Duration(minutes: 30));
    meanwhile();
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
  }

  testAppWidgets('a message that came while the app was in the background '
      'shows in Activity when the app comes back', (tester) async {
    await launch(tester);
    await finishOnboarding(tester);
    await openActivity(tester);

    // The phone tells a sleeping app nothing: the message only reaches the
    // inbox.
    await leaveAndReturn(
      tester,
      meanwhile: () => sms.inbox.add(mpesaTill(receivedAt: now)),
    );

    expect(find.text(_payee), findsOneWidget);
    expect(find.text('-350'), findsOneWidget);
    expect(sms.listenedSenders, hasLength(1), reason: 'never restarted');
  });

  testAppWidgets('starts reading once messages are allowed in the phone\'s '
      'settings', (tester) async {
    sms
      ..current = SmsAccess.denied
      ..inbox.add(mpesaTill());
    await launch(tester);
    await getStarted(tester);
    await tapText(tester, 'M-Pesa');
    await tapText(tester, 'Scan my messages');
    await tapText(tester, 'Do this later');
    await openActivity(tester);

    // Still not allowed: coming back reads nothing.
    await leaveAndReturn(tester, meanwhile: () {});
    expect(sms.reads, isEmpty);
    expect(sms.listenedSenders, isEmpty);
    expect(find.text(_payee), findsNothing);

    await leaveAndReturn(
      tester,
      meanwhile: () => sms.current = SmsAccess.granted,
    );
    expect(find.text(_payee), findsOneWidget);
    expect(sms.listenedSenders.single, {'MPESA'});
  });

  testAppWidgets('with app lock on, the message is there once the PIN is '
      'entered', (tester) async {
    await DriftOnboardingRepository(db).markComplete();
    await DriftInstitutionsRepository(db).setSelected('mpesa', selected: true);
    final vault = testKeyVault(store);
    await vault.setPin(_pin, await vault.readOrCreateOpenKey());
    await vault.writeSettings(const LockSettings(pinSet: true));

    Future<void> enterPin() async {
      for (final digit in _pin.split('')) {
        await tester.tap(find.widgetWithText(TextButton, digit));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    await launch(tester);
    await enterPin();
    await openActivity(tester);

    await leaveAndReturn(
      tester,
      meanwhile: () => sms.inbox.add(mpesaTill(receivedAt: now)),
    );
    expect(find.text(_lockTitle), findsOneWidget);

    await enterPin();
    expect(find.text(_lockTitle), findsNothing);
    expect(find.text(_payee), findsOneWidget);
  });
}
