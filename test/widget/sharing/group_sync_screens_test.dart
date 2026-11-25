import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/sharing/application/group_sync_controller.dart';
import 'package:pesaclarity/src/features/sharing/application/share_providers.dart';
import 'package:pesaclarity/src/features/sharing/presentation/group_sync_widgets.dart';
import 'package:pesaclarity/src/features/sharing/presentation/share_screens.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../domain/fixtures.dart';
import '../../helpers/fake_app_lock.dart';
import '../../helpers/fixed_group_sync.dart';
import '../../helpers/share_phones.dart';
import '../../helpers/test_app.dart';

const _kilimani = Space(
  id: 'kilimani',
  name: 'Home at Kilimani',
  kind: SpaceKind.household,
);

Future<void> _pump(
  WidgetTester tester,
  Phone phone, {
  List<Override> overrides = const [],
}) async {
  phone.now = eat(2026, 11, 22, 9, 41).millisecondsSinceEpoch;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(phone.db),
        clockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(phone.now),
        ),
        activeSpaceProvider.overrideWithValue(_kilimani),
        shareRepositoryProvider.overrideWithValue(phone.repo),
        ...appLockOverrides(),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: const ShareSpaceScreen(spaceId: 'kilimani'),
      ),
    ),
  );
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

final _twoMinAgo = eat(2026, 11, 22, 9, 39);

void main() {
  testWidgets('with the build flag off there is no sync row', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    await _pump(tester, me);
    expect(find.text('Sync automatically'), findsNothing);
    expect(find.text(syncPrivacyNote), findsNothing);
  });

  testWidgets('the owner: switch at the top, own last sync, no per-member '
      'times', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    final sync = FixedGroupSync(
      GroupSyncView(
        phase: GroupSyncPhase.upToDate,
        owner: true,
        lastSyncAt: _twoMinAgo,
      ),
    );
    await _pump(tester, me, overrides: groupSyncOverrides(sync));
    expect(find.text('Sync automatically'), findsOneWidget);
    expect(find.text('Up to date · 2 min ago'), findsOneWidget);
    expect(find.byKey(const Key('sync-switch')), findsOneWidget);
    expect(find.textContaining('Synced'), findsNothing);
    expect(find.text('Joined 3 Nov'), findsOneWidget);
    await scrollTo(tester, find.text('Still works, for anyone not syncing'));
    expect(find.text('UPDATE FILES'), findsOneWidget);
    await scrollTo(tester, find.text(syncPrivacyNote));
    expect(find.text(syncPrivacyNote), findsOneWidget);
  });

  testWidgets('a member sees the status only, with no switch', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    final sync = FixedGroupSync(const GroupSyncView(phase: GroupSyncPhase.off));
    await _pump(tester, me, overrides: groupSyncOverrides(sync));
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Off · only the owner can turn it on'), findsOneWidget);
    expect(find.byKey(const Key('sync-member-status')), findsOneWidget);
  });

  testWidgets('turning on: the sheet, then Premium when it is missing', (
    tester,
  ) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    final sync = FixedGroupSync(
      const GroupSyncView(phase: GroupSyncPhase.off, owner: true),
      turnOnResult: TurnOnResult.needsPremium,
    );
    await _pump(tester, me, overrides: groupSyncOverrides(sync));
    await tester.tap(find.byKey(const Key('sync-switch')));
    await tester.pumpAndSettle();
    expect(find.text('Changes go by themselves'), findsOneWidget);
    expect(find.text('Home at Kilimani · Household'), findsOneWidget);
    await tester.tap(find.text('Turn on sync'));
    await tester.pumpAndSettle();
    expect(sync.turnOns, 1);
    expect(find.text('Sync needs Premium'), findsOneWidget);
    expect(find.textContaining('Jane and Brian sync free'), findsOneWidget);
    await tester.tap(find.text('Keep using update files'));
    await tester.pumpAndSettle();
    expect(find.text('Sync needs Premium'), findsNothing);
  });

  testWidgets('Not now leaves sync off', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    final sync = FixedGroupSync(
      const GroupSyncView(phase: GroupSyncPhase.off, owner: true),
    );
    await _pump(tester, me, overrides: groupSyncOverrides(sync));
    await tester.tap(find.byKey(const Key('sync-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(sync.turnOns, 0);
  });

  testWidgets('no connection is plain, not red', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    final sync = FixedGroupSync(
      const GroupSyncView(
        phase: GroupSyncPhase.offline,
        owner: true,
        toSend: 4,
      ),
    );
    await _pump(tester, me, overrides: groupSyncOverrides(sync));
    final status = find.text('Waiting for a connection · 4 changes to send');
    expect(status, findsOneWidget);
    final error = Theme.of(tester.element(status)).colorScheme.error;
    expect(tester.widget<Text>(status).style?.color, isNot(error));
    expect(find.text('Try again'), findsNothing);
  });

  testWidgets('a sync error: the reason in red, Try again syncs', (
    tester,
  ) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    final sync = FixedGroupSync(
      const GroupSyncView(
        phase: GroupSyncPhase.error,
        owner: true,
        problem: 'unauthorized',
      ),
    );
    await _pump(tester, me, overrides: groupSyncOverrides(sync));
    final rich = tester.widget<Text>(
      find.textContaining('Sync stopped: the server could not check this'),
    );
    final reason = (rich.textSpan! as TextSpan).children!.first as TextSpan;
    expect(
      reason.style!.color,
      Theme.of(tester.element(find.byType(ListView))).colorScheme.error,
    );
    await tester.tap(find.text('Try again'));
    expect(sync.syncs, 1);
  });

  testWidgets("a member after the owner's Premium ended: receiving only", (
    tester,
  ) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    final sync = FixedGroupSync(
      const GroupSyncView(
        phase: GroupSyncPhase.receivingOnly,
        ownerName: 'Achieng',
        toSend: 2,
      ),
    );
    await _pump(tester, me, overrides: groupSyncOverrides(sync));
    expect(
      find.text('Receiving only · 2 changes waiting to send'),
      findsOneWidget,
    );
    expect(find.textContaining("Achieng's Premium has ended."), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('pull to refresh syncs', (tester) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    final sync = FixedGroupSync(
      GroupSyncView(
        phase: GroupSyncPhase.upToDate,
        owner: true,
        lastSyncAt: _twoMinAgo,
      ),
    );
    await _pump(tester, me, overrides: groupSyncOverrides(sync));
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(sync.syncs, 1);
  });

  test('synced ago', () {
    final now = eat(2026, 11, 22, 9, 41);
    expect(syncedAgo(now, now), 'just now');
    expect(syncedAgo(_twoMinAgo, now), '2 min ago');
    expect(syncedAgo(eat(2026, 11, 22, 6, 30), now), '3 h ago');
    expect(syncedAgo(eat(2026, 11, 21, 8), now), 'Sat 21 Nov');
  });
}
