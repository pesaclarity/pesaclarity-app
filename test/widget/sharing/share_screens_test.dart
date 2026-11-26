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
import 'package:pesaclarity/src/features/sharing/application/share_providers.dart';
import 'package:pesaclarity/src/features/sharing/presentation/share_scanner.dart';
import 'package:pesaclarity/src/features/sharing/presentation/share_screens.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/shared/widgets/app_sheet.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/fake_app_lock.dart';
import '../../helpers/share_phones.dart';
import '../../helpers/test_app.dart';

const _kilimani = Space(
  id: 'kilimani',
  name: 'Home at Kilimani',
  kind: SpaceKind.household,
);

class _Picker implements ShareFilePicker {
  _Picker(this.file);

  final List<int> file;

  @override
  Future<(String, List<int>)?> pick() async => ('kilimani-22nov.pcshare', file);
}

Future<void> _pump(
  WidgetTester tester,
  Phone phone,
  Widget home, {
  Space space = _kilimani,
  List<int>? file,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(phone.db),
        clockProvider.overrideWithValue(
          () => DateTime.fromMillisecondsSinceEpoch(phone.now),
        ),
        activeSpaceProvider.overrideWithValue(space),
        shareRepositoryProvider.overrideWithValue(phone.repo),
        if (file != null)
          shareFilePickerProvider.overrideWithValue(_Picker(file)),
        ...appLockOverrides(),
        ...overrides,
      ],
      child: MaterialApp(theme: AppTheme.light, home: home),
    ),
  );
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Share this space lists members, the limit and the note', (
    tester,
  ) async {
    late Phone me;
    await tester.runAsync(() async => (me, _) = await kilimani());
    await _pump(tester, me, const ShareSpaceScreen(spaceId: 'kilimani'));
    expect(find.text('3 of 6'), findsOneWidget);
    expect(find.text('Jane Wairimu'), findsOneWidget);
    expect(find.text('Joined 3 Nov'), findsOneWidget);
    expect(find.text('No account · joined 9 Nov'), findsOneWidget);
    expect(find.text('Last sent to Jane · Fri 20 Nov'), findsOneWidget);
    await scrollTo(tester, find.text(sharePrivacyNote));
    expect(find.text(sharePrivacyNote), findsOneWidget);
    expect(
      find.text('A Household holds up to 6 people, a Savings group up to 30.'),
      findsOneWidget,
    );
  });

  testWidgets('a role: Treasurer only in a chama, Remove in red', (
    tester,
  ) async {
    late Phone me;
    late ShareMember jane;
    await tester.runAsync(() async {
      (me, _) = await kilimani();
      jane = (await me.repo.members()).values.firstWhere(
        (m) => m.name == 'Jane Wairimu',
      );
    });
    await _pump(
      tester,
      me,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showRoleSheet(context, jane),
          child: const Text('Open'),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Treasurer'), findsNothing);
    final remove = tester.widget<Text>(find.text('Remove from group'));
    expect(
      remove.style!.color,
      Theme.of(tester.element(find.text('Remove from group')))
          .colorScheme
          .error,
    );
    await tester.tap(find.byKey(const Key('share-role-viewer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-role-save')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final role = await tester.runAsync(
      () async => (await me.repo.members())[jane.id]!.role,
    );
    expect(role, ShareRole.viewer);
  });

  testWidgets('an update file: what it holds, then Apply', (tester) async {
    late Phone me;
    late List<int> file;
    await tester.runAsync(() async => (me, file) = await kilimani());
    await _pump(
      tester,
      me,
      const ShareSpaceScreen(spaceId: 'kilimani'),
      file: file,
    );
    await tester.tap(find.byKey(const Key('share-receive')));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(
      find.text('From Jane: 14 new, 2 changed, 1 conflict (later wins)'),
      findsOneWidget,
    );
    expect(
      find.textContaining("Jane's is later, so 20,000 stays."),
      findsOneWidget,
    );
    await tester.runAsync(() => me.repo.apply(file));
    final payees = await tester.runAsync(me.payees);
    expect(payees, contains('Naivas'));
  });

  testWidgets('joining: the words, a name, and no account needed', (
    tester,
  ) async {
    late Phone brian;
    late String invite;
    late List<String> words;
    late ShareKeyPair pair;
    await tester.runAsync(() async {
      final jane = Phone('Jane Wairimu');
      await jane.repo.start(myName: 'Jane Wairimu');
      final String request;
      (request, pair, _) = await ShareRepository.makeJoinRequest('Brian');
      (invite, _, words) = await jane.repo.invite(
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
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Join Home at Kilimani'), findsOneWidget);
    expect(find.textContaining("You don't need an account"), findsOneWidget);
    expect(find.text(words.join(' · ')), findsOneWidget);
    expect(find.text('The words match, join'), findsOneWidget);
  });

  testWidgets('an invite made for another phone is not offered', (
    tester,
  ) async {
    late Phone eve;
    late String invite;
    late ShareKeyPair evePair;
    await tester.runAsync(() async {
      final jane = Phone('Jane Wairimu');
      await jane.repo.start(myName: 'Jane Wairimu');
      (invite, _, _) = await jane.repo.invite(
        request: await joinRequest('Brian'),
        role: ShareRole.member,
        spaceName: 'Home at Kilimani',
      );
      (_, evePair, _) = await ShareRepository.makeJoinRequest('Eve');
      eve = Phone('Eve');
    });
    await _pump(
      tester,
      eve,
      JoinSpaceScreen(invite: invite),
      overrides: [
        pendingJoinProvider.overrideWith((ref) async => ('Eve', evePair)),
      ],
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(
      find.text('This invite was made for another phone.'),
      findsOneWidget,
    );
    expect(find.text('The words match, join'), findsNothing);
  });

  group('Add a member', () {
    Future<Phone> owner(WidgetTester tester) async {
      late Phone me;
      await tester.runAsync(() async {
        me = Phone('Achieng');
        await me.repo.start(myName: 'Achieng');
      });
      return me;
    }

    Future<void> open(WidgetTester tester, Phone me, String scanned) async {
      await _pump(
        tester,
        me,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAppSheet<void>(
              context: context,
              builder: (_) => const AddMemberSheet(
                spaceName: 'Home at Kilimani',
                kind: SpaceKind.household,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
        overrides: [
          shareCodeScannerProvider.overrideWithValue(_Scanner(scanned)),
        ],
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('ASK THEM FOR THEIR JOIN REQUEST'), findsOneWidget);
      await tester.tap(find.byKey(const Key('share-request-scan')));
      await tester.pumpAndSettle();
    }

    testWidgets('a scanned join request shows their name and words', (
      tester,
    ) async {
      final me = await owner(tester);
      final made = await tester.runAsync(
        () => ShareRepository.makeJoinRequest('Brian'),
      );
      final (request, _, words) = made!;
      await open(tester, me, request);
      expect(find.text('Add Brian'), findsOneWidget);
      expect(find.text(words.join(' · ')), findsOneWidget);
      expect(find.text('The words match, send the invite'), findsOneWidget);
    });

    testWidgets('a bad code is refused', (tester) async {
      final me = await owner(tester);
      await open(tester, me, 'https://example.com/not-a-request');
      expect(find.text("That isn't a join request."), findsOneWidget);
      expect(find.text('The words match, send the invite'), findsNothing);
    });
  });
}

class _Scanner implements ShareCodeScanner {
  _Scanner(this.text);

  final String text;

  @override
  Future<String?> scan(BuildContext context, ShareCodeKind expect) async =>
      text;
}
