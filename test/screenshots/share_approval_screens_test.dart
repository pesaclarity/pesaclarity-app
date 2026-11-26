// Group approvals, for the accessibility check (tool/accessibility.sh):
// Share this space with changes to approve, Who can change what in a
// Household and a chama, choosing a level, a member who can approve,
// receiving changes that wait, Changes to approve, and a member's own
// waiting change in Activity. Not marketing screenshots, so
// tool/screenshots.sh skips them. Made-up names and amounts.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/sharing/share_model.dart';
import 'package:pesaclarity/src/domain/sharing/share_rules.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/sharing/application/share_providers.dart';
import 'package:pesaclarity/src/features/sharing/presentation/approval_screens.dart';
import 'package:pesaclarity/src/features/sharing/presentation/share_screens.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';
import 'package:pesaclarity/src/shared/widgets/app_sheet.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/share_phones.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

const _kilimani = Space(
  id: 'kilimani',
  name: 'Home at Kilimani',
  kind: SpaceKind.household,
);
const _umoja = Space(
  id: 'umoja',
  name: 'Umoja Savings group',
  kind: SpaceKind.savingsGroup,
);

Future<void> _pump(
  WidgetTester tester,
  Phone phone,
  Widget home, {
  Space space = _kilimani,
  int? tab,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(phone.db),
        personalDatabaseProvider.overrideWithValue(phone.db),
        mainDatabaseProvider.overrideWithValue(phone.db),
        clockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(phone.now),
        ),
        deviceRegionProvider.overrideWithValue('KE'),
        activeSpaceProvider.overrideWithValue(space),
        activeSpaceIdProvider.overrideWith(() => ActiveSpaceId(space.id)),
        spacesProvider.overrideWith(() => _Spaces(space)),
        shareRepositoryProvider.overrideWithValue(phone.repo),
        ...appLockOverrides(),
        ...overrides,
      ],
      child: shotApp(
        tab == null ? home : tabShell(home, tabs: personalTabs, index: tab),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

class _Spaces extends SpacesController {
  _Spaces(this.space);

  final Space space;

  @override
  Future<List<Space>> build() async => [Space.personal, space];
}

Widget _opener(void Function(BuildContext, WidgetRef) open) => Consumer(
  builder: (context, ref, _) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => open(context, ref),
        child: const Text('Open'),
      ),
    ),
  ),
);

/// Umoja: Wanjiku (Owner), Wanjiku Otieno (Treasurer) and Mary Achieng,
/// who can approve, with the chama's rules.
Future<(Phone, ShareMember)> _umojaPhone() async {
  final p = Phone('Wanjiku', kind: SpaceKind.savingsGroup)
    ..now = eat(2026, 11, 22, 9, 41).millisecondsSinceEpoch;
  await p.repo.start(myName: 'Wanjiku');
  late ShareMember mary;
  for (final (name, role) in [
    ('Wanjiku Otieno', ShareRole.treasurer),
    ('Mary Achieng', ShareRole.member),
    ('Otieno Ouma', ShareRole.member),
  ]) {
    final (_, m, _) = await p.repo.invite(
      request: await joinRequest(name),
      role: role,
      spaceName: 'Umoja',
    );
    if (name == 'Mary Achieng') mary = m;
  }
  await p.repo.setApprover(mary.id, approver: true);
  mary = (await p.repo.members())[mary.id]!;
  return (p, mary);
}

void main() {
  if (!checkAccessibility) return;

  screenshot('share-approvals-space', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await waitingKilimani());
    await _pump(tester, me, const ShareSpaceScreen(spaceId: 'kilimani'));
    expect(find.text('2 changes to approve'), findsOneWidget);
    await snap(tester);
  });

  screenshot('share-rules', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await waitingKilimani());
    await _pump(tester, me, const ShareRulesScreen());
    await snap(tester);
  });

  screenshot('share-rules-chama', (tester) async {
    late Phone p;
    await tester.runAsync(() async => (p, _) = await _umojaPhone());
    await _pump(tester, p, const ShareRulesScreen(), space: _umoja);
    await snap(tester);
  });

  screenshot('share-rules-level', (tester) async {
    late Phone p;
    await tester.runAsync(() async => (p, _) = await _umojaPhone());
    await _pump(
      tester,
      p,
      _opener(
        (context, _) => showAppSheet<void>(
          context: context,
          builder: (_) => LevelSheet(
            area: RuleArea.plan,
            policy: SharePolicy.defaults(SpaceKind.savingsGroup),
          ),
        ),
      ),
      space: _umoja,
    );
    await tester.tap(find.text('Open'));
    await _settle(tester);
    await snap(tester);
  });

  screenshot('share-role-approver', (tester) async {
    late Phone p;
    late ShareMember mary;
    await tester.runAsync(() async => (p, mary) = await _umojaPhone());
    await _pump(
      tester,
      p,
      _opener((context, _) => showRoleSheet(context, mary)),
      space: _umoja,
    );
    await tester.tap(find.text('Open'));
    await _settle(tester);
    expect(find.text('Can approve'), findsOneWidget);
    await snap(tester);
  });

  screenshot('share-receive-waiting', (tester) async {
    final me = Phone('Wanjiku');
    late List<int> file;
    await tester.runAsync(() async {
      final jane = Phone('Jane Wairimu');
      final cash = await me.account('Cash box');
      await share(me, {jane: ShareRole.member});
      await me.spend(cash, 'Taxi', 600);
      await me.sendTo(jane);
      await jane.db.customStatement(
        "DELETE FROM transactions WHERE counterparty_name = 'Taxi'",
      );
      final janeCash = (await (jane.db.select(
        jane.db.accounts,
      )..where((a) => a.name.equals('Cash box'))).getSingle()).id;
      for (var i = 1; i <= 5; i++) {
        await jane.spend(janeCash, 'Shop $i', 100 + i);
      }
      final out = await jane.repo.buildUpdate(
        await me.id,
        spaceName: 'Home at Kilimani',
      );
      file = out.bytes;
    });
    final incoming = await tester.runAsync(() => me.repo.preview(file));
    await _pump(
      tester,
      me,
      _opener(
        (context, _) => showAppSheet<void>(
          context: context,
          builder: (_) => ShareReceiveSheet(
            fileName: 'kilimani-22nov.pcshare',
            incoming: incoming!,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await _settle(tester);
    expect(
      find.textContaining('5 new, 2 changed, 1 waiting for your approval'),
      findsOneWidget,
    );
    await snap(tester);
  });

  screenshot('share-approvals', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await waitingKilimani());
    await _pump(tester, me, const ApprovalsScreen());
    expect(find.text('Jane wants to delete "Taxi" (KES 600)'), findsOneWidget);
    await snap(tester);
  });

  screenshot('share-activity-waiting', (tester) async {
    late Phone jane;
    await tester.runAsync(() async => (_, jane) = await waitingKilimani());
    await _pump(tester, jane, const ActivityScreen(), tab: 1);
    expect(find.textContaining('Waiting for approval'), findsWidgets);
    await snap(tester);
  });
}
