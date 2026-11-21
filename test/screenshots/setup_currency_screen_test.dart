// Setup's currency step, for the accessibility check (tool/accessibility.sh):
// on a new phone, and on one whose saved settings cannot be read, each at
// every text size, in light and dark. Not marketing screenshots, so
// tool/screenshots.sh skips them.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/currency/presentation/setup_currency_screen.dart';

import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

/// Settings whose reads fail, as on a phone whose database did not open.
class _Unreadable implements AppSettingsRepository {
  @override
  Future<Map<String, Object?>?> readJson(String key) async =>
      throw StateError('The settings could not be read');

  @override
  Future<void> writeJson(String key, Map<String, Object?> value) async {}
}

void main() {
  if (!checkAccessibility) return;

  Future<void> pump(WidgetTester tester, {bool unreadable = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(openTestDatabase()),
          deviceRegionProvider.overrideWithValue('KE'),
          if (unreadable)
            appSettingsRepositoryProvider.overrideWithValue(_Unreadable()),
          ...appLockOverrides(),
        ],
        child: shotApp(const SetupCurrencyScreen()),
      ),
    );
    await settleFrames(tester);
    await tester.pumpAndSettle();
  }

  screenshot('setup-currency', (tester) async {
    await pump(tester);
    await snap(tester);
  });

  screenshot('setup-currency-unreadable', (tester) async {
    await pump(tester, unreadable: true);
    await snap(tester);
  });
}
