import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/features/plan/presentation/plan_screen.dart';
import 'package:pesaclarity/src/features/reminders/application/reminders_controller.dart';
import 'package:pesaclarity/src/features/reminders/presentation/reminders_settings_card.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/test_app.dart';
import 'plan_screen_test.dart' as plan;

void main() {
  testAppWidgets('a category over its plan shows a card at the top of Plan', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => plan.seedNovember(db));
    await plan.pumpScreen(tester, db, const PlanScreen());

    expect(find.text('Eating out is over its plan'), findsOneWidget);
    expect(find.textContaining('1,420 over, 5 days left'), findsOneWidget);
    // Transport, at 58%, waits for 80%.
    expect(find.textContaining('Transport'), findsWidgets);
    expect(find.text('Transport is over its plan'), findsNothing);
  });

  testAppWidgets('a category gets its own share from its Plan row', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => plan.seedNovember(db));
    await plan.pumpScreen(tester, db, const PlanScreen());

    final transport = find.text('Transport').first;
    await tester.ensureVisible(transport);
    await tester.pumpAndSettle();
    await tester.tap(transport);
    await tester.pumpAndSettle();
    expect(find.text('Warn me at'), findsOneWidget);
    expect(find.text('Same as all (80%)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('category-warn-at')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('warn-at-50')).last);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Its own share: Transport warns at 50%'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(find.textContaining('warns at 50%'), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.text('Transport has used 58% of its plan'), findsOneWidget);
  });

  testAppWidgets('bills show as a calendar, and the choice is kept', (
    tester,
  ) async {
    final db = openTestDatabase();
    await tester.runAsync(() => plan.seedNovember(db));
    await plan.pumpScreen(tester, db, const PlanScreen());

    final calendar = find.byKey(const Key('plan-bills-calendar'));
    await tester.scrollUntilVisible(calendar, 300);
    await tester.tap(calendar);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('bills-calendar')), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
    // Today, Thursday 26 November, has nothing due.
    await tester.scrollUntilVisible(find.text('THU 26 NOV'), 300);
    expect(find.text('THU 26 NOV'), findsOneWidget);
    expect(find.text('Nothing is due on this day.'), findsOneWidget);

    final fifth = find.byKey(const Key('bills-day-5'));
    await tester.ensureVisible(fifth);
    await tester.pumpAndSettle();
    await tester.tap(fifth);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('THU 5 NOV'), 300);
    expect(find.text('THU 5 NOV'), findsOneWidget);
    expect(find.text('Rent'), findsWidgets);
    expect(find.text('Paid'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await plan.pumpScreen(tester, db, const PlanScreen());
    await tester.scrollUntilVisible(
      find.byKey(const Key('bills-calendar')),
      300,
    );
    expect(find.byKey(const Key('bills-calendar')), findsOneWidget);
  });

  testAppWidgets('Profile sets when budget alerts come', (tester) async {
    final db = openTestDatabase();
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => plan.now),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                return const SingleChildScrollView(
                  child: RemindersSettingsCard(),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Budget alerts'), findsWidgets);
    expect(find.text('Again when over'), findsOneWidget);
    expect(find.text('Amounts on lock screen'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('budget-alert-share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('warn-at--2')).last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('custom-share')), '200');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Type a whole number from 10 to 150.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('custom-share')), '65');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('65%'), findsOneWidget);
    expect(
      container.read(remindersControllerProvider).value?.budgetAlertPercent,
      65,
    );
  });
}
