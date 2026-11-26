// Sharing a Household or Savings group space by file (decision 0031, stage
// 1), for the accessibility check (tool/accessibility.sh): the Sharing row
// in a space's settings, Share this space, a member's role in a chama,
// adding a member, an update file ready to send, receiving one, Activity
// with who added each transaction, Space history and joining, and group
// sync (fx-14). Not marketing screenshots, so tool/screenshots.sh skips
// them. Made-up names and amounts.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/share/share_codec.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/share_repository.dart';
import 'package:pesaclarity/src/domain/sharing/share_model.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/activity/presentation/activity_screen.dart';
import 'package:pesaclarity/src/features/backup/application/backup_providers.dart';
import 'package:pesaclarity/src/features/backup/data/backup_sharing.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/sharing/application/group_sync_controller.dart';
import 'package:pesaclarity/src/features/sharing/application/share_providers.dart';
import 'package:pesaclarity/src/features/sharing/presentation/group_sync_widgets.dart';
import 'package:pesaclarity/src/features/sharing/presentation/share_scanner.dart';
import 'package:pesaclarity/src/features/sharing/presentation/share_screens.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/spaces/presentation/manage_spaces_screens.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';
import 'package:pesaclarity/src/shared/widgets/app_sheet.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/fixed_group_sync.dart';
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

/// Pumps [home] on [phone]'s database, in [space].
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

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

/// Umoja, a chama of 14, made by Wanjiku, with Mary Otieno as Treasurer.
Future<(Phone, ShareMember)> _umojaPhone() async {
  final p = Phone('Wanjiku', kind: SpaceKind.savingsGroup)
    ..now = eat(2026, 11, 22, 9, 41).millisecondsSinceEpoch;
  await p.repo.start(myName: 'Wanjiku');
  late ShareMember chosen;
  for (var i = 1; i < 14; i++) {
    final (_, m, _) = await p.repo.invite(
      request: await joinRequest(i == 1 ? 'Wanjiku Otieno' : 'Member $i'),
      role: i == 1 ? ShareRole.treasurer : ShareRole.member,
      spaceName: 'Umoja',
    );
    if (i == 1) chosen = m;
  }
  return (p, chosen);
}

void main() {
  if (!checkAccessibility) return;

  screenshot('share-space-settings', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    await _pump(tester, me, const SpaceSettingsScreen(spaceId: 'kilimani'));
    await snap(tester);
  });

  screenshot('share-space', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    await _pump(tester, me, const ShareSpaceScreen(spaceId: 'kilimani'));
    await snap(tester);
  });

  screenshot('share-role', (tester) async {
    late Phone p;
    late ShareMember m;
    await tester.runAsync(() async => (p, m) = await _umojaPhone());
    await _pump(
      tester,
      p,
      _opener((context, _) => showRoleSheet(context, m)),
      space: _umoja,
    );
    await _open(tester);
    await snap(tester);
  });

  screenshot('share-add-member', (tester) async {
    late Phone me;
    late String request;
    await tester.runAsync(() async {
      (me, _) = await kilimani();
      request = await joinRequest('Otieno Ouma');
    });
    await _pump(
      tester,
      me,
      _opener(
        (context, _) => showAppSheet<void>(
          context: context,
          builder: (_) => const AddMemberSheet(
            spaceName: 'Home at Kilimani',
            kind: SpaceKind.household,
          ),
        ),
      ),
      overrides: [
        shareCodeScannerProvider.overrideWithValue(_Scanner(request)),
        fileSharerProvider.overrideWithValue(_NoSharing()),
      ],
    );
    await _open(tester);
    await snap(tester);
    await tester.ensureVisible(find.byKey(const Key('share-request-scan')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-request-scan')));
    await tester.pumpAndSettle();
    await snap(tester, variant: 'request');
    await tester.ensureVisible(find.byKey(const Key('share-invite-make')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-invite-make')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await snap(tester, variant: 'invite');
  });

  screenshot('share-join-request', (tester) async {
    final phone = Phone('Brian');
    await _pump(
      tester,
      phone,
      const JoinRequestScreen(),
      overrides: [pendingJoinProvider.overrideWith((ref) async => null)],
    );
    await snap(tester);
  });

  screenshot('share-join-request-ready', (tester) async {
    final phone = Phone('Brian');
    final made = await tester.runAsync(
      () => ShareRepository.makeJoinRequest('Brian'),
    );
    await _pump(
      tester,
      phone,
      const JoinRequestScreen(),
      overrides: [
        pendingJoinProvider.overrideWith((ref) async => ('Brian', made!.$2)),
      ],
    );
    await snap(tester);
  });

  screenshot('share-send', (tester) async {
    late Phone me;
    late OutgoingShare out;
    await tester.runAsync(() async {
      (me, _) = await kilimani();
      final jane = (await me.repo.members()).values.firstWhere(
        (m) => m.name == 'Jane Wairimu',
      );
      await me.db.customStatement(
        "UPDATE share_peers SET words_checked = 0 WHERE member_id = '${jane.id}'",
      );
      out = await me.repo.buildUpdate(jane.id, spaceName: 'Home at Kilimani');
    });
    await _pump(
      tester,
      me,
      _opener(
        (context, _) => showAppSheet<void>(
          context: context,
          builder: (_) =>
              ShareSendSheet(spaceName: 'Home at Kilimani', out: out),
        ),
      ),
    );
    await _open(tester);
    await snap(tester);
  });

  screenshot('share-receive', (tester) async {
    late Phone me;
    late List<int> file;
    await tester.runAsync(() async => (me, file) = await kilimani());
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
    await _open(tester);
    expect(
      find.text('From Jane: 14 new, 2 changed, 1 conflict (later wins)'),
      findsOneWidget,
    );
    await snap(tester);
  });

  screenshot('share-activity', (tester) async {
    late Phone me;
    await tester.runAsync(() async {
      late List<int> file;
      (me, file) = await kilimani();
      await me.repo.apply(file);
    });
    await _pump(tester, me, const ActivityScreen(), tab: 1);
    expect(find.text('Added by Jane'), findsWidgets);
    await snap(tester);
  });

  screenshot('share-history', (tester) async {
    late Phone me;
    await tester.runAsync(() async {
      late List<int> file;
      (me, file) = await kilimani();
      await me.repo.apply(file);
    });
    await _pump(tester, me, const SpaceHistoryScreen());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await snap(tester);
  });

  screenshot('share-join', (tester) async {
    late Phone brian;
    late String invite;
    late ShareKeyPair pair;
    await tester.runAsync(() async {
      final jane = Phone('Jane Wairimu');
      await jane.repo.start(myName: 'Jane Wairimu');
      final String request;
      (request, pair, _) = await ShareRepository.makeJoinRequest('Brian');
      (invite, _, _) = await jane.repo.invite(
        request: request,
        role: ShareRole.member,
        spaceName: 'Home at Kilimani',
      );
      brian = Phone('Brian');
    });
    await _pump(
      tester,
      brian,
      JoinSpaceScreen(invite: invite),
      overrides: [
        pendingJoinProvider.overrideWith((ref) async => ('Brian', pair)),
      ],
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    await snap(tester);
  });

  // Group sync (decision 0033, fx-14), behind the build's sync switch.
  Future<void> syncShot(WidgetTester tester, GroupSyncView view) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    me.now = eat(2026, 11, 22, 9, 41).millisecondsSinceEpoch;
    await _pump(
      tester,
      me,
      const ShareSpaceScreen(spaceId: 'kilimani'),
      overrides: groupSyncOverrides(FixedGroupSync(view)),
    );
    await snap(tester);
  }

  screenshot(
    'group-sync-on',
    (tester) => syncShot(
      tester,
      GroupSyncView(
        phase: GroupSyncPhase.upToDate,
        owner: true,
        lastSyncAt: eat(2026, 11, 22, 9, 39),
      ),
    ),
  );

  screenshot(
    'group-sync-offline',
    (tester) => syncShot(
      tester,
      const GroupSyncView(
        phase: GroupSyncPhase.offline,
        owner: true,
        toSend: 4,
      ),
    ),
  );

  screenshot(
    'group-sync-error',
    (tester) => syncShot(
      tester,
      const GroupSyncView(
        phase: GroupSyncPhase.error,
        owner: true,
        problem: 'unauthorized',
      ),
    ),
  );

  screenshot(
    'group-sync-receiving-only',
    (tester) => syncShot(
      tester,
      const GroupSyncView(
        phase: GroupSyncPhase.receivingOnly,
        ownerName: 'Achieng',
        toSend: 2,
      ),
    ),
  );

  screenshot(
    'group-sync-member-off',
    (tester) =>
        syncShot(tester, const GroupSyncView(phase: GroupSyncPhase.off)),
  );

  screenshot('group-sync-turn-on', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    await _pump(
      tester,
      me,
      _opener(
        (context, _) => showAppSheet<void>(
          context: context,
          builder: (_) => const TurnOnSyncSheet(space: _kilimani),
        ),
      ),
    );
    await _open(tester);
    await snap(tester);
  });

  screenshot('group-sync-needs-premium', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    await _pump(
      tester,
      me,
      _opener(
        (context, _) => showAppSheet<void>(
          context: context,
          builder: (_) =>
              const SyncNeedsPremiumSheet(others: ['Jane', 'Brian']),
        ),
      ),
    );
    await _open(tester);
    await snap(tester);
  });
}

class _Scanner implements ShareCodeScanner {
  _Scanner(this.text);

  final String text;

  @override
  Future<String?> scan(BuildContext context, ShareCodeKind expect) async =>
      text;
}

class _NoSharing implements FileSharer {
  @override
  Future<void> shareFile(
    File file, {
    required String subject,
    String? text,
  }) async {}

  @override
  Future<void> shareText(String text, {required String subject}) async {}
}
