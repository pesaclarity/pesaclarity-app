import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';

import '../helpers/fake_sms_source.dart';
import '../helpers/sms_samples.dart';
import '../helpers/test_app.dart';

void main() {
  late AppDatabase db;
  // Monday 26 October 2026, 18:00 EAT, the day the sample messages came.
  var now = DateTime.utc(2026, 10, 26, 15);

  setUp(() {
    db = openTestDatabase();
    now = DateTime.utc(2026, 10, 26, 15);
  });

  Future<void> pump(WidgetTester tester, {FakeSmsSource? sms}) => pumpApp(
    tester,
    db: db,
    sms: sms,
    overrides: [clockProvider.overrideWithValue(() => now)],
  );

  /// Setup up to "Your money", with the till payment filed as groceries.
  Future<void> toYourMoney(WidgetTester tester) async {
    final sms = FakeSmsSource(
      inbox: [mpesaSent(), mpesaTill()],
      current: SmsAccess.granted,
    );
    addTearDown(sms.close);
    await pump(tester, sms: sms);
    await getStarted(tester);
    await tapText(tester, 'M-Pesa');
    await tapText(tester, 'Scan my messages');
    await tapText(tester, 'Allow access to messages');
    await tester.runAsync(() async {
      final groceries = await (db.select(
        db.categories,
      )..where((c) => c.key.equals('groceries'))).getSingle();
      await (db.update(
        db.transactions,
      )..where((t) => t.receiptNo.equals('TJA0000004'))).write(
        TransactionsCompanion(categoryOverrideId: Value(groceries.id)),
      );
    });
    await tapText(tester, 'Continue');
  }

  Future<void> openTab(WidgetTester tester, String name) async {
    await tester.tap(
      find.descendant(
        of: find.byType(PillNavigationBar),
        matching: find.text(name),
      ),
    );
    await tester.pumpAndSettle();
  }

  testAppWidgets('Your money offers About you; the answers start Plan and '
      'Goals suggests one goal', (tester) async {
    await toYourMoney(tester);
    expect(find.text('Make it yours'), findsOneWidget);
    // Go to Home stays the main button.
    await scrollTo(tester, find.text('Go to Home'));
    expect(find.widgetWithText(FilledButton, 'Go to Home'), findsOneWidget);

    await tapText(tester, 'Answer 3 questions');
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('Which best describes you now?'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.textContaining('income'), findsNothing);
    await tester.tap(find.byKey(const Key('about-why')));
    await tester.pumpAndSettle();
    expect(
      find.text('It picks which goal we suggest. Nothing else changes.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('who-working')));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byKey(const Key('who-working'))),
      matchesSemantics(
        label: 'Working or in business\nA job, a business or both',
        hasCheckedState: true,
        isChecked: true,
        isInMutuallyExclusiveGroup: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    await tapText(tester, 'Continue');

    expect(find.text('2 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('matters-saveSteadily')));
    await tester.pumpAndSettle();
    await tapText(tester, 'Continue');

    expect(find.text('Which do you pay regularly?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pays-groceries')));
    await tester.tap(find.byKey(const Key('pays-rent')));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Continue'));
    await tester.tap(find.text('Continue'));
    // Plan is worked out from real records: let them finish.
    await settleFrames(tester);
    await tester.pumpAndSettle();
    expect(find.byType(PillNavigationBar), findsOneWidget);

    // Groceries, from the 350 paid over three months; Rent shows in no
    // message, so it waits for the person.
    final bills = await tester.runAsync(() => db.select(db.recurring).get());
    expect(
      [for (final b in bills!) (b.name, b.amountMinor)],
      [('Groceries', 20000)],
    );
    final saved = await tester.runAsync(
      () => (db.select(
        db.appSettings,
      )..where((s) => s.key.equals('aboutYou'))).getSingle(),
    );
    expect(saved!.value, contains('"who":"working"'));

    await openTab(tester, 'Goals');
    await settleFrames(tester);
    await tester.pumpAndSettle();
    expect(find.text('Start an emergency fund?'), findsOneWidget);
    expect(
      find.textContaining('You said saving steadily matters.'),
      findsOneWidget,
    );
    await tapText(tester, 'Add this goal');
    expect(find.text('Start an emergency fund?'), findsNothing);
    expect(find.text('Emergency fund'), findsOneWidget);
  });

  testAppWidgets(
    'skipped at setup, it is offered once more in Things to sort, then '
    'only in Profile',
    (tester) async {
      await toYourMoney(tester);
      await tester.scrollUntilVisible(find.text('Go to Home'), 200);
      await tapText(tester, 'Go to Home');
      expect(find.byKey(const Key('home-about-you')), findsNothing);

      // The next day.
      now = now.add(const Duration(days: 1));
      await pump(tester);
      await openThingsToSort(tester);
      await scrollTo(tester, find.byKey(const Key('home-about-you')));
      await tester.tap(find.byKey(const Key('about-offer-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-about-you')), findsNothing);

      now = now.add(const Duration(days: 1));
      await pump(tester);
      expect(find.byKey(const Key('home-about-you')), findsNothing);

      await tester.tap(find.byTooltip('Profile'));
      await tester.pumpAndSettle();
      await tapText(tester, 'About you');
      expect(find.text('Which best describes you now?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('about-skip-all')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Profile'), findsOneWidget);
    },
  );
}
