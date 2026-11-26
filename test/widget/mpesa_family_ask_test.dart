import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/savings_repository.dart';
import 'package:pesaclarity/src/domain/accounts/mpesa_family.dart';
import 'package:pesaclarity/src/features/accounts/presentation/choose_accounts_screen.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/statements/data/pdf_text_extractor.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';
import '../screenshots/mpesa_family_records.dart';

// The M-Pesa family asked about before it is added (decision 0026 item 5),
// on a made-up month of M-Pesa (mpesa_family_records.dart).

Future<void> _pump(WidgetTester tester, AppDatabase db, Widget home) async {
  // Tall enough that every row is built.
  tester.view.physicalSize = const Size(800, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        personalDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => familyNow),
        pdfTextExtractorProvider.overrideWithValue(null),
        activeSpaceIdProvider.overrideWith(ActiveSpaceId.new),
        smsParseBatchProvider.overrideWithValue(
          (packs, messages) async => parseAll(packs, messages),
        ),
      ],
      child: MaterialApp(theme: AppTheme.light, home: home),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

Future<List<Account>> _accounts(WidgetTester tester, AppDatabase db) async =>
    (await tester.runAsync(() => db.select(db.accounts).get()))!;

void main() {
  testAppWidgets('Activity asks about M-Shwari under its newest move; Add '
      'makes it, and the next one is asked', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => FamilyRecords(db).seed(answered: false));
    await _pump(tester, db, const ActivityScreen());

    expect(find.text('You have M-Shwari savings. Add it?'), findsOneWidget);
    // Its moves wait as own transfers, not spending.
    expect(find.text('M-Pesa → M-Shwari'), findsNothing);
    expect(find.text('Own transfer · not spending'), findsNWidgets(6));
    expect(
      (await _accounts(tester, db)).where((a) => a.product != null),
      isEmpty,
    );

    await tester.tap(find.byKey(const Key('savings-prompt-add')));
    await _settle(tester);
    expect(
      (await _accounts(tester, db)).where((a) => a.product == 'mshwari'),
      hasLength(1),
    );
    expect(find.text('You have M-Shwari savings. Add it?'), findsNothing);
    expect(
      find.text('M-Shwari added · 1 older payment updated'),
      findsOneWidget,
    );
    expect(find.text('You have Ziidi. Add it?'), findsOneWidget);
  });

  testAppWidgets('Not now is kept, and Add or remove accounts offers it '
      'later', (tester) async {
    final db = openTestDatabase();
    await tester.runAsync(() => FamilyRecords(db).seed(answered: false));
    await _pump(tester, db, const ActivityScreen());

    await tester.tap(find.byKey(const Key('savings-prompt-decline')));
    await _settle(tester);
    expect(find.text('You have M-Shwari savings. Add it?'), findsNothing);
    expect(await tester.runAsync(() => DriftSavingsRepository(db).declined()), {
      'mshwari',
    });

    // Pochi la Biashara: asked on top, off the records.
    expect(find.text('You have Pochi la Biashara. Add it?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pochi-prompt-decline')));
    await _settle(tester);
    expect(find.text('You have Pochi la Biashara. Add it?'), findsNothing);

    await _pump(tester, db, const ChooseAccountsScreen());
    await scrollTo(tester, find.byKey(const Key('savings-add-mshwari')));
    expect(find.byKey(const Key('savings-add-pochi')), findsOneWidget);
    await tester.tap(find.byTooltip('Add M-Shwari'));
    await _settle(tester);
    await tester.tap(find.byTooltip('Add Pochi'));
    await _settle(tester);
    final accounts = await _accounts(tester, db);
    expect(accounts.where((a) => a.product == 'mshwari'), hasLength(1));
    expect(accounts.where((a) => isPochiReference(a.reference)), hasLength(1));
    expect(find.byKey(const Key('savings-add-mshwari')), findsNothing);
    expect(find.byKey(const Key('savings-add-pochi')), findsNothing);
  });
}
