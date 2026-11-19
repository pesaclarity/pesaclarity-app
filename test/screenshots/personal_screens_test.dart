// Personal screens for the marketing screenshots: a made-up salaried
// person's months, drawn by the app's own widgets (README, Screenshots).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/debts/presentation/debts_screen.dart';
import 'package:pesaclarity/src/features/goals/presentation/goals_screen.dart';
import 'package:pesaclarity/src/features/home/presentation/home_screen.dart';
import 'package:pesaclarity/src/features/insights/presentation/insights_screen.dart';
import 'package:pesaclarity/src/features/plan/presentation/plan_screen.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';

import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';
import 'personal_records.dart';

/// [screen] in the personal tab bar; over [root] when given.
Widget _shell(Widget screen, int tab, {Widget? root}) =>
    tabShell(screen, tabs: personalTabs, index: tab, root: root);

Future<void> _pump(WidgetTester tester, Widget home) async {
  final db = openTestDatabase();
  await tester.runAsync(() => PersonalRecords(db).seed());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => personalNow),
        deviceRegionProvider.overrideWithValue('KE'),
        activeSpaceProvider.overrideWithValue(Space.personal),
        ...appLockOverrides(),
      ],
      child: shotApp(home),
    ),
  );
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

void main() {
  screenshot('home', (tester) async {
    await _pump(tester, _shell(const HomeScreen(), 0));
    await snap(tester);
  });

  screenshot('plan', (tester) async {
    await _pump(tester, _shell(const PlanScreen(), 2));
    await snap(tester);
  });

  screenshot('goals', (tester) async {
    await _pump(tester, _shell(const GoalsScreen(), 3));
    await snap(tester);
  });

  screenshot('debts', (tester) async {
    await _pump(
      tester,
      _shell(const DebtsScreen(), 3, root: const GoalsScreen()),
    );
    // Three steps along the what-if slider, scrolled into view first.
    await tester.dragUntilVisible(
      find.byType(Slider),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    final slider = tester.getRect(find.byType(Slider));
    await tester.tapAt(
      Offset(slider.left + 24 + (slider.width - 48) * 0.15, slider.center.dy),
    );
    await tester.pumpAndSettle();
    await snap(tester);
  });

  screenshot('insights', (tester) async {
    await _pump(tester, _shell(const InsightsScreen(), 4));
    await snap(tester);
  });
}
