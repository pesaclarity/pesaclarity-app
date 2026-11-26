// Chumz as a savings account fed from M-Pesa, for the accessibility check
// (tool/accessibility.sh): Activity with the question under the first
// payment, Activity once Chumz is added, My accounts, Chumz's page and
// Goals, each at every text size, in light, dark and high contrast. Not
// marketing screenshots, so tool/screenshots.sh skips them. Made-up
// records (savings_records.dart).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/accounts/presentation/my_accounts_settings_screen.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/goals/presentation/goals_screen.dart';
import 'package:pesaclarity/src/features/savings/presentation/savings_account_screen.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/statements/data/pdf_text_extractor.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';

import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';
import 'savings_records.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget Function(int? accountId) home, {
  bool added = true,
  bool balances = true,
}) async {
  final db = openTestDatabase();
  final accountId = await tester.runAsync(() async {
    final records = SavingsRecords(db);
    final seeded = await records.seed();
    return added ? records.addChumz(seeded, balances: balances) : null;
  });
  await tester.pumpWidget(_scope(db, home(accountId)));
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

Widget _scope(AppDatabase db, Widget home) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    personalDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => savingsNow),
    deviceRegionProvider.overrideWithValue('KE'),
    activeSpaceProvider.overrideWithValue(Space.personal),
    pdfTextExtractorProvider.overrideWithValue(null),
    ...appLockOverrides(),
  ],
  child: shotApp(home),
);

Widget _shell(Widget screen, int tab) =>
    tabShell(screen, tabs: personalTabs, index: tab);

void main() {
  if (!checkAccessibility) return;

  screenshot('savings-prompt', (tester) async {
    await _pump(tester, (_) => _shell(const ActivityScreen(), 1), added: false);
    await snap(tester);
  });

  screenshot('savings-added', (tester) async {
    // Just added, before any balance is typed.
    await _pump(
      tester,
      (_) => _shell(const ActivityScreen(), 1),
      balances: false,
    );
    await snap(tester);
  });

  screenshot('savings-my-accounts', (tester) async {
    await _pump(tester, (_) => const MyAccountsSettingsScreen());
    await snap(tester);
  });

  screenshot('savings-account', (tester) async {
    await _pump(tester, (id) => SavingsAccountScreen(accountId: id!));
    await snap(tester);
  });

  screenshot('savings-goals', (tester) async {
    await _pump(tester, (_) => _shell(const GoalsScreen(), 3));
    await snap(tester);
  });
}
