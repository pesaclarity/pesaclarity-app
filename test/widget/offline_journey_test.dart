import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/app.dart';
import 'package:pesaclarity/src/core/backup/recovery_key.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/auth/application/auth_controller.dart';
import 'package:pesaclarity/src/features/backup/data/backup_settings_repository.dart';
import 'package:pesaclarity/src/features/crash_reports/presentation/crash_report_sheet.dart';
import 'package:pesaclarity/src/features/privacy/application/consent_controller.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/routing/app_router.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/shared/semantic_ids.dart';

import '../helpers/offline_harness.dart';
import '../helpers/sms_samples.dart';
import '../helpers/test_app.dart';

/// The app works fully offline: the usual journeys with no network show
/// nothing broken, nothing stuck and no crash, and the online-only actions
/// say calmly that they need a connection.

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(PesaClarityApp)));

Future<void> _tap(WidgetTester tester, OfflinePhone phone, Finder f) async {
  phone.log.add('tap ${f.describeMatch(Plurality.one)}');
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(f.first);
  await tester.pump();
  await tester.tap(f.first);
  await settleOffline(tester, phone);
}

Future<void> _go(WidgetTester tester, OfflinePhone phone, String route) async {
  _container(tester).read(appRouterProvider).go(route);
  await settleOffline(tester, phone);
}

Future<void> _push(
  WidgetTester tester,
  OfflinePhone phone,
  String route,
) async {
  // Not awaited: the route's future completes only when it is popped.
  unawaited(_container(tester).read(appRouterProvider).push<void>(route));
  await settleOffline(tester, phone);
}

Future<void> _back(WidgetTester tester, OfflinePhone phone) async {
  final router = _container(tester).read(appRouterProvider);
  if (router.canPop()) router.pop();
  await settleOffline(tester, phone);
}

/// Lets file and crypto work (a backup) finish on the real event loop.
Future<void> _settleWork(WidgetTester tester, OfflinePhone phone) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await settleOffline(tester, phone);
}

/// Lets a note's few seconds pass, as a person reading it would.
Future<void> _wait(WidgetTester tester, OfflinePhone phone) async {
  await tester.pump(const Duration(seconds: 5));
  await settleOffline(tester, phone);
}

void _expectCalm(OfflinePhone phone, String step) {
  final screen = observeOffline(phone, step);
  expect(screen.calm, isTrue, reason: '$step: $screen\n$phone');
}

void _expectNote(OfflinePhone phone, String step, String note) {
  final screen = observeOffline(phone, step);
  expect(screen.notes, [note], reason: '$step\n${phone.log}');
}

void _expectNothingBroke(OfflinePhone phone) {
  expect(phone.log.uncaught, isEmpty, reason: '${phone.log}');
  expect(phone.crashes.reports, isEmpty, reason: '${phone.log}');
}

/// Finishes setup offline, from a new phone to Home.
Future<void> _setUp(WidgetTester tester, OfflinePhone phone) async {
  await coldStartOffline(tester, phone);
  await finishOnboarding(tester);
  await settleOffline(tester, phone);
  if (find.text('Go to Home').evaluate().isNotEmpty) {
    await tester.tap(find.text('Go to Home'));
    await settleOffline(tester, phone);
  }
  // A person who has agreed to the bundled policy, as after the policy
  // review an upgrade shows.
  await tester.runAsync(
    () =>
        _container(tester)
            .read(consentControllerProvider.notifier)
            .accept(bundledPolicy()),
  );
  await settleOffline(tester, phone);
  // A business space, so switching is possible.
  await tester.runAsync(
    () => DriftAppSettingsRepository(phone.personal).writeJson(
      SpacesController.settingsKey,
      spacesToJson([
        Space.personal,
        const Space(id: 'shop1', name: 'Mama Mboga', kind: SpaceKind.business),
      ]),
    ),
  );
}

/// Backups set up to the vault and the SD card.
Future<void> _setUpBackups(WidgetTester tester, OfflinePhone phone) =>
    tester.runAsync(() async {
      final repo = BackupSettingsRepository(phone.backupStore);
      await repo.writeSecrets(
        BackupSecrets(
          passphrase: 'made-up passphrase for tests',
          recoveryKey: RecoveryKey.generate(),
        ),
      );
      await repo.save(
        (await repo.load()).copyWith(
          enabled: {BackupLocationId.vault, BackupLocationId.deviceFolder},
          folder: const DeviceFolder(uri: 'content://tree/sd', name: 'SD card'),
        ),
      );
    });

void _resumeAfter(WidgetTester tester, OfflinePhone phone, Duration away) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  phone.now = phone.now.add(away);
  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

/// Home, the tabs, Profile, Backups, Ask and switching spaces, then a
/// night away: nothing about being offline shows anywhere.
Future<void> _usualDay(
  WidgetTester tester,
  OfflinePhone phone, {
  required bool signedIn,
}) async {
  await coldStartOffline(tester, phone);
  _expectCalm(phone, 'cold start');
  for (final (id, name) in [
    (SemanticIds.navActivity, 'activity'),
    (SemanticIds.navPlan, 'plan'),
    (SemanticIds.navInsights, 'insights'),
    (SemanticIds.navHome, 'home'),
  ]) {
    await _tap(tester, phone, find.bySemanticsIdentifier(id));
    _expectCalm(phone, name);
  }
  await _tap(tester, phone, find.byTooltip('Profile'));
  await tester.scrollUntilVisible(
    find.text(signedIn ? 'Sign out' : 'Sign in'),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await settleOffline(tester, phone);
  _expectCalm(phone, 'profile, account section');
  await _go(tester, phone, AppRoutes.home);
  await _push(tester, phone, AppRoutes.backup);
  _expectCalm(phone, 'backups');
  await _back(tester, phone);
  await _push(tester, phone, AppRoutes.ask);
  await tester.enterText(
    find.byType(TextField).first,
    'How much did I spend on food?',
  );
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await settleOffline(tester, phone);
  _expectCalm(phone, 'ask');
  await _go(tester, phone, AppRoutes.home);

  await _tap(tester, phone, find.byKey(const Key('home-space')));
  await _tap(tester, phone, find.text('Mama Mboga'));
  _expectCalm(phone, 'business');
  await _tap(tester, phone, find.byKey(const Key('home-space')));
  await _tap(tester, phone, find.text('Personal'));
  _expectCalm(phone, 'back to personal');

  // Past the rates' age, the app-status interval and the session's.
  _resumeAfter(tester, phone, const Duration(hours: 14));
  await settleOffline(tester, phone);
  await tester.pump(const Duration(minutes: 30));
  await settleOffline(tester, phone);
  _expectCalm(phone, 'resumed after a night');
}

void main() {
  setUpAll(loadOfflineFonts);

  testWidgets('first run, fully offline', (tester) async {
    offlinePhoneView(tester);
    mockOfflineChannels(tester);
    final phone = OfflinePhone();
    phone.sms.inbox.addAll([
      mpesaSent(receivedAt: DateTime(2026, 11, 20, 9)),
      mpesaTill(receivedAt: DateTime(2026, 11, 20, 13)),
    ]);
    await coldStartOffline(tester, phone);
    _expectCalm(phone, 'welcome');

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'name@example.com',
      ),
      'wanjiru@example.com',
    );
    await _tap(tester, phone, find.text('Send code'));
    expect(
      find.text(
        'Signing in needs a connection. Everything else works offline.',
      ),
      findsOneWidget,
    );

    await finishOnboarding(tester);
    await settleOffline(tester, phone);
    if (find.text('Go to Home').evaluate().isNotEmpty) {
      await _tap(tester, phone, find.text('Go to Home'));
    }
    expect(find.byTooltip('Profile'), findsOneWidget, reason: 'on Home');
    _expectCalm(phone, 'home');
    _expectNothingBroke(phone);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('signed in, offline, after a night away', (tester) async {
    offlinePhoneView(tester);
    mockOfflineChannels(tester);
    final phone = OfflinePhone();
    phone.sms.inbox.add(mpesaSent(receivedAt: DateTime(2026, 11, 20, 9)));
    await _setUp(tester, phone);
    await _setUpBackups(tester, phone);
    phone.sessions.session = signedInYesterday;

    await _usualDay(tester, phone, signedIn: true);
    expect(phone.sessions.session, isNotNull, reason: 'still signed in');

    // Back up now: the SD card gets its copy; the vault waits.
    await _push(tester, phone, AppRoutes.backup);
    await _tap(tester, phone, find.text('Back up now'));
    await _settleWork(tester, phone);
    expect(phone.documents.written, hasLength(1));
    _expectNote(
      phone,
      'back up now',
      'Backed up to SD card. The vault needs a connection; it will back up '
          'when you are online.',
    );
    await _back(tester, phone);
    await _wait(tester, phone);

    await _push(tester, phone, AppRoutes.baseCurrency);
    await _tap(tester, phone, find.text('Refresh rates'));
    _expectNote(
      phone,
      'refresh rates',
      'Rates update once you are online. Try again soon.',
    );
    await _back(tester, phone);
    await _wait(tester, phone);
    _expectCalm(phone, 'the rates note has gone');

    await _push(tester, phone, AppRoutes.devices);
    final devices = observeOffline(phone, 'signed-in phones');
    expect(devices.errors, ['This list needs a connection. | Try again']);
    expect(find.textContaining('Signing in'), findsNothing);
    await _back(tester, phone);

    // Restart, still offline.
    await coldStartOffline(tester, phone);
    _expectCalm(phone, 'second cold start');
    expect(
      await tester.runAsync(
        () => _container(tester).read(authControllerProvider.future),
      ),
      isNotNull,
    );

    // Delete the business space, backing up first, with its online copy.
    await _push(tester, phone, AppRoutes.spaceSettings('shop1'));
    await _tap(tester, phone, find.byKey(const Key('space-delete')));
    phone.now = phone.now.add(const Duration(minutes: 1));
    await _tap(tester, phone, find.text('Back up first'));
    await _settleWork(tester, phone);
    expect(phone.documents.written, hasLength(2));
    _expectNote(
      phone,
      'back up first',
      'Backed up to SD card. The vault needs a connection; it will back up '
          'when you are online.',
    );
    await _wait(tester, phone);
    await _tap(tester, phone, find.byKey(const Key('keep-30-days')));
    await _tap(tester, phone, find.byKey(const Key('delete-online')));
    await tester.enterText(
      find.byKey(const Key('space-delete-name')),
      'Mama Mboga',
    );
    await settleOffline(tester, phone);
    await _tap(tester, phone, find.byKey(const Key('space-delete-confirm')));
    expect(phone.files.deleted, ['shop1']);
    expect(find.byKey(const Key('space-delete-confirm')), findsNothing);
    _expectNote(
      phone,
      'delete with the online copy',
      'Deleted on this phone. The online copy will be deleted when you are '
          'online.',
    );
    final waiting = await tester.runAsync(
      () => BackupSettingsRepository(phone.backupStore).load(),
    );
    expect(waiting!.pendingOnlineDeletes.keys, ['shop1']);
    expect(waiting.vaultPending, isTrue);

    expect(phone.sessions.session, isNotNull, reason: 'never signed out');
    _expectNothingBroke(phone);

    // Sign out offline: done on this phone, as today.
    await coldStartOffline(tester, phone);
    _expectCalm(phone, 'third cold start');
    await _push(tester, phone, AppRoutes.profile);
    await _tap(tester, phone, find.text('Sign out'));
    expect(phone.sessions.session, isNull);
    _expectNote(
      phone,
      'sign out',
      'Signed out on this phone. To remove it from your account, sign it '
          'out from another phone under Signed-in phones.',
    );
    _expectNothingBroke(phone);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('a crash report is asked about on the next start, and Send '
      'report offline does not ask again', (tester) async {
    offlinePhoneView(tester);
    mockOfflineChannels(tester);
    final phone = OfflinePhone();
    await _setUp(tester, phone);
    await tester.runAsync(() => phone.capture(StateError('made up')));

    await coldStartOffline(tester, phone);
    final asked = observeOffline(phone, 'start after a crash');
    expect(
      asked.sheets.single,
      startsWith(CrashReportSheet.title),
      reason: '${phone.log}',
    );
    expect(find.byTooltip('Profile'), findsOneWidget, reason: 'over Home');
    await _tap(tester, phone, find.text(CrashReportSheet.send));
    expect(phone.crashes.reports, isEmpty);
    expect(phone.crashes.toSend, hasLength(1), reason: 'sent once online');

    await coldStartOffline(tester, phone);
    _expectCalm(phone, 'next start, still offline');
    expect(phone.crashes.toSend, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }, timeout: const Timeout(Duration(minutes: 8)));

  testWidgets('no account, offline', (tester) async {
    offlinePhoneView(tester);
    mockOfflineChannels(tester);
    final phone = OfflinePhone();
    phone.sms.inbox.add(mpesaSent(receivedAt: DateTime(2026, 11, 20, 9)));
    await _setUp(tester, phone);
    await _usualDay(tester, phone, signedIn: false);

    await _push(tester, phone, AppRoutes.baseCurrency);
    await _tap(tester, phone, find.text('Refresh rates'));
    _expectNote(
      phone,
      'refresh rates',
      'Rates update once you are online. Try again soon.',
    );
    await _back(tester, phone);

    await coldStartOffline(tester, phone);
    _expectCalm(phone, 'second cold start');
    _expectNothingBroke(phone);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
  }, timeout: const Timeout(Duration(minutes: 8)));
}
