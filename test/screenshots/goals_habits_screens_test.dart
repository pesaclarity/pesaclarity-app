// Keeping a goal aside, no-spend days and the Sunday check-in, for the
// accessibility check (tool/accessibility.sh): each sheet and card at every
// text size, in light and dark. Not marketing screenshots, so
// tool/screenshots.sh skips them. Every name and amount is made up.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/goals_repository.dart';
import 'package:pesaclarity/src/domain/goals/goals_aside.dart';
import 'package:pesaclarity/src/domain/goals/savings_goal.dart';
import 'package:pesaclarity/src/domain/habits/no_spend_days.dart';
import 'package:pesaclarity/src/domain/habits/week_check_in.dart';
import 'package:pesaclarity/src/domain/ledger/on_hand.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';
import 'package:pesaclarity/src/features/balances/presentation/on_hand_sheet.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/goals/application/goals_aside_providers.dart';
import 'package:pesaclarity/src/features/goals/presentation/goal_dip_sheet.dart';
import 'package:pesaclarity/src/features/goals/presentation/goal_sheet.dart';
import 'package:pesaclarity/src/features/habits/application/habits_providers.dart';
import 'package:pesaclarity/src/features/habits/presentation/habits_home_cards.dart';
import 'package:pesaclarity/src/features/habits/presentation/habits_settings_card.dart';
import 'package:pesaclarity/src/features/habits/presentation/habits_sheets.dart';
import 'package:pesaclarity/src/features/home/application/goal_dips_provider.dart';
import 'package:pesaclarity/src/features/home/presentation/goal_dip_cards.dart';
import 'package:pesaclarity/src/features/insights/application/insights_providers.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

/// Sunday 22 November 2026, 9:41.
final _now = eat(2026, 11, 22, 9, 41);
final _today = CalendarDate.local(_now);

final _schoolFees = SavingsGoal(
  id: 1,
  name: 'School fees',
  targetMinor: kes(45000),
  savedMinor: kes(20000),
  targetDate: CalendarDate(2027, 1, 31),
);

NoSpendDays _week() => NoSpendDays.of(
  [
    entry(at: eat(2026, 11, 16), amount: kes(1240)),
    entry(at: eat(2026, 11, 18), amount: kes(380)),
    entry(at: eat(2026, 11, 19), amount: kes(2100)),
    entry(at: eat(2026, 11, 20), amount: kes(1800), categoryId: 9),
  ],
  today: _today,
  historyFrom: CalendarDate(2026, 11, 1),
  scheduledCategoryIds: {9},
);

WeekCheckIn _checkIn() => WeekCheckIn(
  start: CalendarDate(2026, 11, 16),
  end: _today,
  spentMinor: kes(3700),
  lastWeekMinor: kes(7800),
  noSpendDays: 3,
  noSpendBestThisMonth: true,
  mostChanged: (categoryId: 1, changeMinor: -kes(3000)),
  aboveUsual: (categoryId: 2, changeMinor: kes(1900)),
  usualMinor: kes(1500),
);

List<Override> _data() => [
  noSpendDaysProvider.overrideWith((ref) async => _week()),
  weekCheckInProvider.overrideWith((ref) async => _checkIn()),
  categoryNamesProvider.overrideWith(
    (ref) => Stream.value(const {1: 'Eating out', 2: 'Transport'}),
  ),
  goalDipsProvider.overrideWith(
    (ref) async => [
      GoalDip(goal: _schoolFees, dipMinor: kes(1500), asideMinor: kes(20000)),
    ],
  ),
  onHandProvider.overrideWith(
    (ref) async => OnHand(
      byAccount: {1: kes(33069), 2: kes(12000)},
      rainyDayMinor: kes(5000),
      fulizaOwedMinor: 0,
      goalsWantedMinor: kes(20000),
    ),
  ),
  goalsAsideProvider.overrideWith(
    (ref) async =>
        GoalsAside([GoalAside(goal: _schoolFees, asideMinor: kes(20000))]),
  ),
];

/// Registers [name]: [body] on a plain screen, or, with [open], an empty
/// screen that opens it. Only in the accessibility check.
void _shot(
  String name, {
  Widget body = const SizedBox.shrink(),
  void Function(BuildContext context)? open,
  Future<void> Function(AppDatabase db)? seed,
  bool withData = true,
}) {
  if (!checkAccessibility) return;
  screenshot(name, (tester) async {
    final db = openTestDatabase();
    if (seed != null) await tester.runAsync(() => seed(db));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          personalDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(() => _now),
          deviceRegionProvider.overrideWithValue('KE'),
          activeSpaceProvider.overrideWithValue(Space.personal),
          ...appLockOverrides(),
          if (withData) ..._data(),
        ],
        child: shotApp(
          Scaffold(
            body: Builder(
              builder: (context) => ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  body,
                  if (open != null)
                    TextButton(
                      onPressed: () => open(context),
                      child: const Text('Open'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await settleFrames(tester);
    if (open != null) {
      await tester.tap(find.text('Open'));
      await settleFrames(tester);
    }
    await tester.pumpAndSettle();
    await snap(tester);
  });
}

void main() {
  late SavingsGoal kept;
  _shot(
    'goal-sheet-keep-aside',
    withData: false,
    open: (c) => showGoalSheet(c, today: _today, goal: kept),
    seed: (db) async {
      final goals = DriftGoalsRepository(db);
      final id = await goals.add(
        name: 'School fees',
        targetMinor: kes(45000),
        savedMinor: kes(20000),
        targetDate: CalendarDate(2027, 1, 31),
      );
      await DriftAppSettingsRepository(db).writeJson(
        KeptAsideController.settingsKey,
        const KeptAsideSettings().withKept(id, kept: true).toJson(),
      );
      kept = (await goals.goals()).single;
    },
  );
  _shot('on-hand-goals', open: showOnHandSheet);
  _shot(
    'goal-dip-sheet',
    open: (c) => showGoalDipSheet(
      c,
      today: _today,
      dip: GoalDip(
        goal: _schoolFees,
        dipMinor: kes(1500),
        asideMinor: kes(20000),
      ),
    ),
  );
  _shot(
    'home-goals-habits-cards',
    body: const Column(
      children: [GoalDipCards(), SundayCheckInCard(), NoSpendCard()],
    ),
  );
  _shot('no-spend-week', open: (c) => showNoSpendWeekSheet(c, _week()));
  _shot('week-check-in', open: (c) => showWeekCheckInSheet(c, _checkIn()));
  _shot('profile-habits', body: const HabitsSettingsCard());
}
