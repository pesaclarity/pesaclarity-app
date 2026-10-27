import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/core/backup/backup.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/features/backup/application/backup_providers.dart';
import 'package:pesaclarity/src/features/backup/application/backup_service.dart';
import 'package:pesaclarity/src/features/backup/data/backup_settings_repository.dart';
import 'package:pesaclarity/src/features/backup/data/key_value_store.dart';
import 'package:pesaclarity/src/features/backup/presentation/backup_screen.dart';
import 'package:pesaclarity/src/features/backup/presentation/backup_setup_screen.dart';
import 'package:pesaclarity/src/features/profile/presentation/profile_screen.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import 'backup_fakes.dart';

final _now = DateTime(2026, 10, 26, 18);

Future<R> _inline<R>(FutureOr<R> Function() work) async => work();

class _Harness {
  _Harness() : store = MemoryKeyValueStore();

  final MemoryKeyValueStore store;
  final documents = FakeDocumentStorage();
  final sharer = FakeFileSharer();
  final printer = FakeDocumentPrinter();
  final data = FakeLocalDataStore(List.generate(2000, (i) => i % 100));
  late final Directory work = Directory.systemTemp.createTempSync('ui');

  BackupSettingsRepository get repo => BackupSettingsRepository(store);

  List<Override> overrides(AppFlavor flavor) => [
    appFlavorProvider.overrideWithValue(flavor),
    clockProvider.overrideWithValue(() => _now),
    backupKeyValueStoreProvider.overrideWithValue(store),
    documentStorageProvider.overrideWithValue(documents),
    fileSharerProvider.overrideWithValue(sharer),
    documentPrinterProvider.overrideWithValue(printer),
    recoveryKeyScratchDirectoryProvider.overrideWithValue(Future.value(work)),
    backupServiceProvider.overrideWith(
      (ref) => BackupService(
        data: data,
        settings: ref.watch(backupSettingsRepositoryProvider),
        workDirectory: () async => work,
        clock: () => _now,
        kdfParams: const KdfParams(
          memoryKiB: 256,
          iterations: 1,
          parallelism: 1,
        ),
        runner: _inline,
      ),
    ),
  ];

  Future<void> pump(
    WidgetTester tester, {
    AppFlavor flavor = AppFlavor.foss,
  }) async {
    addTearDown(() => work.deleteSync(recursive: true));
    final router = GoRouter(
      initialLocation: AppRoutes.backup,
      routes: [
        GoRoute(
          path: AppRoutes.backup,
          builder: (context, state) => const BackupScreen(),
          routes: [
            GoRoute(
              path: 'setup',
              builder: (context, state) => const BackupSetupScreen(),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(flavor),
        child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _setUpSecrets(_Harness h) => h.repo.writeSecrets(
  BackupSecrets(
    passphrase: 'John anapenda chai',
    recoveryKey: RecoveryKey.generate(),
  ),
);

/// Lets file and crypto work finish on the real event loop.
Future<void> _settleWork(WidgetTester tester) async {
  for (var i = 0; i < 300; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    final busy =
        find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    if (!busy && i >= 5) break;
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the design sections before setup', (tester) async {
    final h = _Harness();
    await h.pump(tester);

    expect(find.text('Backup and restore'), findsOneWidget);
    expect(find.text('Set up encrypted backups'), findsOneWidget);
    expect(find.text('BACK UP TO'), findsOneWidget);
    expect(find.text('Pesa Clarity vault'), findsOneWidget);
    expect(find.text('Available when the vault service opens'), findsOneWidget);
    expect(find.text('Phone or SD card'), findsOneWidget);
    expect(find.text('Back up now'), findsOneWidget);
    expect(find.text('Share a copy'), findsOneWidget);
    expect(find.text('RESTORE FROM'), findsOneWidget);
    expect(find.text('A file on this phone'), findsOneWidget);
    expect(
      find.textContaining('Your current data stays until the restore'),
      findsOneWidget,
    );
    // F-Droid build: no Google Drive at all.
    expect(find.text('My Google Drive'), findsNothing);
    expect(find.text('Google Drive'), findsNothing);

    // The vault stays off until a build names its server.
    final vault = tester.widget<CheckboxListTile>(
      find.descendant(
        of: find.byKey(const Key('backup-vault')),
        matching: find.byType(CheckboxListTile),
      ),
    );
    expect(vault.value, isFalse);
    expect(vault.onChanged, isNull);
  });

  testWidgets('the Play build lists Google Drive', (tester) async {
    final h = _Harness();
    await h.pump(tester, flavor: AppFlavor.play);
    expect(find.text('My Google Drive'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
  });

  testWidgets('setup shows the recovery key once and needs confirmation', (
    tester,
  ) async {
    final h = _Harness();
    await h.pump(tester);

    await tester.tap(find.text('Set up'));
    await tester.pumpAndSettle();
    expect(find.text('Set up backups'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'short');
    await tester.enterText(find.byType(TextFormField).at(1), 'short');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'mvua ya jioni');
    await tester.enterText(find.byType(TextFormField).at(1), 'mvua ya asubuhi');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('The two passphrases differ.'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(1), 'mvua ya jioni');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Your recovery key'), findsOneWidget);
    final shown = tester
        .widget<SelectableText>(find.byKey(const Key('recovery-key-text')))
        .data!;
    expect(shown.replaceAll(RegExp(r'\s'), ''), hasLength(56));

    await tester.tap(find.text('Print'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(h.printer.printed, 1);

    await tester.tap(find.text('Share as text'));
    await tester.pumpAndSettle();
    expect(h.sharer.shared.single, contains('Pesa Clarity recovery key'));

    final finish = find.widgetWithText(FilledButton, 'Finish');
    expect(tester.widget<FilledButton>(finish).onPressed, isNull);
    await tester.tap(find.text('I have saved my recovery key somewhere safe'));
    await tester.pumpAndSettle();
    await tester.tap(finish);
    await tester.pumpAndSettle();

    expect(find.text('Ready to back up'), findsOneWidget);
    final secrets = await h.repo.readSecrets();
    expect(secrets?.passphrase, 'mvua ya jioni');
    expect(
      RecoveryKey.parse(shown.replaceAll(RegExp(r'\s'), '')),
      secrets?.recoveryKey,
    );
  });

  testWidgets('backs up to a chosen folder and shows the time', (tester) async {
    final h = _Harness();
    await _setUpSecrets(h);
    await h.pump(tester);

    await tester.tap(find.text('Phone or SD card'));
    await tester.pumpAndSettle();
    expect(h.documents.folderPicks, 1);
    expect(find.textContaining('Pesa Clarity · offline'), findsOneWidget);

    await tester.tap(find.text('Back up now'));
    await _settleWork(tester);

    expect(h.documents.written.keys, ['pesaclarity-2026-10-26-1800.pcbackup']);
    expect(find.text('Backed up today, 18:00'), findsOneWidget);
    expect(
      find.text('Encrypted with your passphrase before upload'),
      findsOneWidget,
    );
  });

  testWidgets('restores from the folder only with the right passphrase', (
    tester,
  ) async {
    final h = _Harness();
    await _setUpSecrets(h);
    await h.pump(tester);
    await tester.tap(find.text('Phone or SD card'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back up now'));
    await _settleWork(tester);
    final original = h.data.contents;
    h.data.contents = [9, 9, 9];

    await tester.tap(find.text('See backups ›'));
    await _settleWork(tester);
    expect(find.text('Backups in Pesa Clarity'), findsOneWidget);
    await tester.tap(find.text('today, 18:00'));
    await _settleWork(tester);
    expect(find.text('Restore this backup'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('restore-secret')), 'chai');
    await tester.tap(find.text('Restore'));
    await _settleWork(tester);
    expect(
      find.text('That passphrase or recovery key does not open this backup.'),
      findsOneWidget,
    );
    expect(h.data.replacements, 0);
    expect(h.data.contents, [9, 9, 9]);

    await tester.enterText(
      find.byKey(const Key('restore-secret')),
      'John anapenda chai',
    );
    await tester.tap(find.text('Restore'));
    await _settleWork(tester);
    expect(h.data.replacements, 1);
    expect(h.data.contents, original);
    expect(
      find.text('Restored. Your data is from today, 18:00.'),
      findsOneWidget,
    );
  });

  testWidgets('Profile shows where and when the last backup went', (
    tester,
  ) async {
    final h = _Harness();
    await h.repo.save(
      BackupSettings(
        enabled: const {BackupLocationId.deviceFolder},
        lastSuccessAt: DateTime(2026, 10, 26, 6, 10),
        lastSuccessTo: const {BackupLocationId.deviceFolder},
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: h.overrides(AppFlavor.foss),
        child: MaterialApp(theme: AppTheme.light, home: const ProfileScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SD card · today'), findsOneWidget);
    // Unmount so the database's stream queries close inside the fake clock.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(Duration.zero);
    h.work.deleteSync(recursive: true);
  });
}
