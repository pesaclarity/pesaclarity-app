// The M-Pesa family of accounts (decision 0026), for the accessibility
// check (tool/accessibility.sh): My accounts with M-Pesa closed and opened,
// What you own and owe, Ziidi's and M-Shwari's pages, Activity, Activity
// asking "You have M-Shwari savings. Add it?" and about Pochi before the
// person answers, and the Track Fuliza switch row on and off, each at
// every text size, in light, dark and high contrast. Not marketing
// screenshots, so tool/screenshots.sh skips them. Made-up records
// (mpesa_family_records.dart).
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/fuliza_tracking.dart';
import 'package:pesaclarity/src/data/repositories/transactions_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/accounts/presentation/my_accounts_settings_screen.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/savings/presentation/savings_account_screen.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/statements/data/pdf_text_extractor.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';

import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';
import 'mpesa_family_records.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget Function(FamilySeeded seeded) home, {
  bool answered = true,
}) async {
  final db = openTestDatabase();
  final seeded = await tester.runAsync(
    () => FamilyRecords(db).seed(answered: answered),
  );
  await tester.pumpWidget(_scope(db, home(seeded!)));
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

/// The family's M-Pesa after a made-up Fuliza draw, so My accounts offers
/// Track Fuliza; [tracked] is the switch.
Future<void> _pumpWithFuliza(
  WidgetTester tester, {
  required bool tracked,
}) async {
  final db = openTestDatabase();
  await tester.runAsync(() async {
    await FamilyRecords(db).seed();
    final mpesa = await (db.select(
      db.accounts,
    )..where((a) => a.type.equalsValue(AccountType.mpesa))).get();
    await DriftTransactionsRepository(db).addNew([
      TransactionsCompanion.insert(
        accountId: mpesa.first.id,
        occurredAt: familyNow.subtract(const Duration(hours: 2)),
        amountMinor: 25000,
        direction: TransactionDirection.inflow,
        kind: const Value(TransactionKind.fulizaDraw),
        feeMinor: const Value(250),
        source: TransactionSource.sms,
        dedupeKey: const Value('shot-fuliza'),
        receiptNo: const Value('TMF9999999'),
      ),
    ]);
    if (!tracked) {
      await DriftAppSettingsRepository(db)
          .writeJson(trackFulizaKey, {'track': false});
    }
  });
  await tester.pumpWidget(_scope(db, const MyAccountsSettingsScreen()));
  await settleFrames(tester);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('track-fuliza')),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Widget _scope(AppDatabase db, Widget home) => ProviderScope(
  overrides: [
    appDatabaseProvider.overrideWithValue(db),
    personalDatabaseProvider.overrideWithValue(db),
    clockProvider.overrideWithValue(() => familyNow),
    deviceRegionProvider.overrideWithValue('KE'),
    activeSpaceProvider.overrideWithValue(Space.personal),
    pdfTextExtractorProvider.overrideWithValue(null),
    ...appLockOverrides(),
  ],
  child: shotApp(home),
);

void main() {
  if (!checkAccessibility) return;

  screenshot('mpesa-family-accounts', (tester) async {
    await _pump(tester, (_) => const MyAccountsSettingsScreen());
    await snap(tester);
  });

  screenshot('mpesa-family-accounts-open', (tester) async {
    await _pump(tester, (_) => const MyAccountsSettingsScreen());
    final toggle = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('mpesa-family-toggle'),
    );
    await tester.scrollUntilVisible(
      toggle,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    await snap(tester);
  });

  screenshot('mpesa-family-own-and-owe', (tester) async {
    await _pump(tester, (_) => const MyAccountsSettingsScreen());
    await tester.tap(find.byKey(const Key('own-and-owe')));
    await tester.pumpAndSettle();
    await snap(tester);
  });

  screenshot('mpesa-track-fuliza-on', (tester) async {
    await _pumpWithFuliza(tester, tracked: true);
    await snap(tester);
  });

  screenshot('mpesa-track-fuliza-off', (tester) async {
    await _pumpWithFuliza(tester, tracked: false);
    await snap(tester);
  });

  screenshot('mpesa-family-ziidi', (tester) async {
    await _pump(tester, (s) => SavingsAccountScreen(accountId: s.ziidi!));
    await snap(tester);
  });

  screenshot('mpesa-family-mshwari', (tester) async {
    await _pump(tester, (s) => SavingsAccountScreen(accountId: s.mshwari!));
    await snap(tester);
  });

  // Before the person answers (decision 0026 item 5): Pochi's question on
  // top, and "You have M-Shwari savings. Add it?" under its newest move.
  screenshot('mpesa-family-prompt', (tester) async {
    await _pump(
      tester,
      (_) => tabShell(const ActivityScreen(), tabs: personalTabs, index: 1),
      answered: false,
    );
    expect(find.byKey(const Key('pochi-prompt')), findsOneWidget);
    await snap(tester);
    final prompt = find.byKey(const Key('savings-prompt'));
    await tester.scrollUntilVisible(
      prompt,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('You have M-Shwari savings. Add it?'), findsOneWidget);
  });

  screenshot('mpesa-family-activity', (tester) async {
    await _pump(
      tester,
      (_) => tabShell(const ActivityScreen(), tabs: personalTabs, index: 1),
    );
    await snap(tester);
  });
}
