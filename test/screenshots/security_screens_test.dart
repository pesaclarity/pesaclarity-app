// Profile's Security card, for the accessibility check
// (tool/accessibility.sh): every row, with screenshots blocked and then
// allowed, each at every text size, in light and dark. Not marketing
// screenshots, so tool/screenshots.sh skips them. A made-up PIN.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/features/security/application/app_lock_controller.dart';
import 'package:pesaclarity/src/features/security/data/screen_capture_blocker.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/security/domain/lock_settings.dart';
import 'package:pesaclarity/src/features/security/presentation/security_settings_card.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';

import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

const _pin = '246810';

void main() {
  if (!checkAccessibility) return;
  screenshot('security', (tester) async {
    final db = openTestDatabase();
    // App lock and fingerprint unlock on, so the card shows every row.
    final store = MemorySecureStore();
    await tester.runAsync(() async {
      final vault = testKeyVault(store);
      final key = await vault.readOrCreateOpenKey();
      await vault.setPin(_pin, key);
      await vault.enableBiometric(key);
      await vault.writeSettings(
        const LockSettings(pinSet: true, biometricEnabled: true),
      );
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          personalDatabaseProvider.overrideWithValue(db),
          ...appLockOverrides(
            store: store,
            biometrics: FakeBiometricAuthenticator(available: true),
          ),
          screenCaptureBlockerProvider.overrideWithValue(
            FakeScreenCaptureBlocker(),
          ),
          // As on Android: an iPhone has no screenshots row.
          canBlockScreenCaptureProvider.overrideWithValue(true),
        ],
        child: shotApp(
          Scaffold(
            appBar: AppBar(
              title: const Text('Profile'),
              actions: const [AmountsEye(), SizedBox(width: 8)],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: const [SecuritySettingsCard()],
            ),
          ),
        ),
      ),
    );
    await settleFrames(tester);
    // Unlocked, as Profile always is.
    final lock = ProviderScope.containerOf(
      tester.element(find.byType(SecuritySettingsCard)),
    ).read(appLockControllerProvider.notifier);
    await tester.runAsync(() => lock.enterPin(_pin));
    await tester.pumpAndSettle();
    await snap(tester);

    final allow = find.text('Allow screenshots and screen recording');
    await tester.ensureVisible(allow);
    await tester.pumpAndSettle();
    await tester.tap(allow);
    await settleFrames(tester);
    await tester.pumpAndSettle();
    await snap(tester, variant: 'security-allowed');
  });
}
