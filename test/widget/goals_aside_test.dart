import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
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
import 'package:pesaclarity/src/domain/ledger/on_hand.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/balances/application/balances_providers.dart';
import 'package:pesaclarity/src/features/balances/presentation/on_hand_sheet.dart';
import 'package:pesaclarity/src/features/goals/application/goals_aside_providers.dart';
import 'package:pesaclarity/src/features/goals/presentation/goal_sheet.dart';
import 'package:pesaclarity/src/features/home/application/goal_dips_provider.dart';
import 'package:pesaclarity/src/features/home/presentation/goal_dip_cards.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/goals_harness.dart';
import '../helpers/test_app.dart';

int _kes(int shillings) => shillings * 100;

Future<int> _seed(AppDatabase db, {int mpesa = 50000}) async {
  await db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: 'M-Pesa',
          type: AccountType.mpesa,
          openingBalanceMinor: Value(_kes(mpesa)),
          openingDate: DateTime.utc(2026, 9),
        ),
      );
  return DriftGoalsRepository(db).add(
    name: 'School fees',
    targetMinor: _kes(45000),
    savedMinor: _kes(20000),
    targetDate: CalendarDate(2027, 1, 31),
  );
}

/// [child] in an app on [db], with a button that opens what [open] shows.
Future<void> _pumpOpener(
  WidgetTester tester, {
  required AppDatabase db,
  required void Function(BuildContext context) open,
  List<Override> overrides = const [],
  Widget? above,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => goalsTestNow),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                ?above,
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
  await settle(tester);
}

void main() {
  testAppWidgets('Keep it aside on a goal, then Kept aside on its card', (
    tester,
  ) async {
    final db = openTestDatabase();
    final id = await tester.runAsync(() => _seed(db));
    await pumpGoals(tester, db: db);

    await tester.scrollUntilVisible(find.text('School fees'), 200);
    expect(find.byKey(Key('goal-kept-aside-$id')), findsNothing);
    await tester.tap(find.text('School fees'));
    await settle(tester);

    expect(find.text('Keep it aside'), findsOneWidget);
    expect(
      find.text('The 20,000 saved leaves Safe to spend and On hand'),
      findsOneWidget,
    );
    expect(find.textContaining('not a bank lock'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('goal-keep-aside')));
    await tester.tap(find.byKey(const Key('goal-keep-aside')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This is not a bank lock. The money stays where it is and you can '
        'still spend it. Pesa Clarity just stops counting it as free.',
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await settle(tester);

    await tester.scrollUntilVisible(find.text('School fees'), 200);
    expect(find.byKey(Key('goal-kept-aside-$id')), findsOneWidget);
    expect(find.text('Kept aside'), findsOneWidget);
    final saved = await tester.runAsync(
      () =>
          DriftAppSettingsRepository(db)
              .readJson(KeptAsideController.settingsKey),
    );
    expect(KeptAsideSettings.fromJson(saved).isKept(id!), isTrue);
  });

  test('a goal kept aside comes off On hand; a dip shows once free money '
      'runs out', () async {
    final db = openTestDatabase();
    final id = await _seed(db, mpesa: 18500);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => goalsTestNow),
      ],
    );
    addTearDown(container.dispose);
    expect(
      (await container.read(onHandProvider.future))!.totalMinor,
      _kes(18500),
    );

    await container.read(keptAsideProvider.notifier).setKept(id, kept: true);
    final onHand = (await container.read(onHandProvider.future))!;
    expect(onHand.totalMinor, 0);
    expect(onHand.goalsAsideMinor, _kes(18500));
    final dip = (await container.read(goalDipsProvider.future)).single;
    expect(dip.dipMinor, _kes(1500));
    expect(dip.seen, isFalse);

    // "Leave it as it is": the goal keeps showing 20,000, 18,500 aside.
    await container.read(keptAsideProvider.notifier).leave(id, dip.dipMinor);
    container.invalidate(goalsAsideProvider);
    expect(await container.read(goalDipsProvider.future), isEmpty);
    expect(
      (await container.read(onHandProvider.future))!.goalsWantedMinor,
      _kes(18500),
    );
  });

  testAppWidgets('a goal in a savings app has no switch', (tester) async {
    final db = openTestDatabase();
    await _pumpOpener(
      tester,
      db: db,
      open: (c) => showGoalSheet(
        c,
        today: CalendarDate.local(goalsTestNow),
        goal: SavingsGoal(
          id: 1,
          name: 'Christmas',
          targetMinor: _kes(10000),
          savedMinor: _kes(5000),
          backing: const GoalBacking(
            accountId: 1,
            accountName: 'Chumz',
            pocketId: 1,
            pocketName: 'Christmas',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await settle(tester);
    expect(find.text('Edit Christmas'), findsOneWidget);
    expect(find.text('Keep it aside'), findsNothing);
  });

  testAppWidgets('On hand names what is set aside for goals', (tester) async {
    final db = openTestDatabase();
    final goal = SavingsGoal(
      id: 1,
      name: 'School fees',
      targetMinor: _kes(45000),
      savedMinor: _kes(20000),
    );
    await _pumpOpener(
      tester,
      db: db,
      open: showOnHandSheet,
      overrides: [
        onHandProvider.overrideWith(
          (ref) async => OnHand(
            byAccount: {1: _kes(45069)},
            rainyDayMinor: _kes(5000),
            fulizaOwedMinor: 0,
            goalsWantedMinor: _kes(20000),
          ),
        ),
        goalsAsideProvider.overrideWith(
          (ref) async =>
              GoalsAside([GoalAside(goal: goal, asideMinor: _kes(20000))]),
        ),
      ],
    );
    await tester.tap(find.text('Open'));
    await settle(tester);
    expect(find.text('On hand: KES 20,069'), findsOneWidget);
    expect(find.text('Set aside for goals'), findsOneWidget);
    expect(find.text('-20,000'), findsOneWidget);
    expect(
      find.textContaining('Safe to spend leaves out what you keep aside'),
      findsOneWidget,
    );
  });

  testAppWidgets('a dip: the card, then lowering what is saved', (
    tester,
  ) async {
    final db = openTestDatabase();
    final id = await tester.runAsync(() => _seed(db));
    await tester.runAsync(
      () => DriftAppSettingsRepository(db).writeJson(
        KeptAsideController.settingsKey,
        const KeptAsideSettings().withKept(id!, kept: true).toJson(),
      ),
    );
    final goal = SavingsGoal(
      id: id!,
      name: 'School fees',
      targetMinor: _kes(45000),
      savedMinor: _kes(20000),
      targetDate: CalendarDate(2027, 1, 31),
    );
    await _pumpOpener(
      tester,
      db: db,
      open: (_) {},
      above: const GoalDipCards(),
      overrides: [
        goalDipsProvider.overrideWith(
          (ref) async => [
            GoalDip(goal: goal, dipMinor: _kes(1500), asideMinor: _kes(20000)),
          ],
        ),
      ],
    );
    expect(find.text('You dipped KES 1,500 into School fees'), findsOneWidget);
    expect(
      find.text(
        'Your free money ran out, so this came from what you set aside',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(Key('home-goal-dip-$id')));
    await settle(tester);
    expect(
      find.text(
        'It happens. The goal still shows 20,000 saved, but only 18,500 is '
        'aside now.',
      ),
      findsOneWidget,
    );
    expect(find.text('Top it up from the next money in'), findsOneWidget);
    expect(
      find.text(
        'The 1,500 comes back to the goal first when money comes in. Nothing '
        'moves in your bank or M-Pesa.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('goal-dip-answer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('goal-dip-lower')).last);
    await tester.pumpAndSettle();
    // October to January: four months for the 26,500 left.
    expect(
      find.text(
        'School fees shows 18,500 of 45,000, and its monthly pace goes up '
        'to 6,625.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('goal-dip-done')));
    await settle(tester);
    final goals = await tester.runAsync(() => DriftGoalsRepository(db).goals());
    expect(goals!.single.savedMinor, _kes(18500));
  });
}
