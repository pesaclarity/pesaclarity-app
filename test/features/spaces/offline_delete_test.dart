import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pesaclarity/src/core/backup/backup.dart';
import 'package:pesaclarity/src/core/network/reachability.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/auth/application/auth_controller.dart';
import 'package:pesaclarity/src/features/auth/data/session_store.dart';
import 'package:pesaclarity/src/features/auth/domain/auth_models.dart';
import 'package:pesaclarity/src/features/backup/application/backup_providers.dart';
import 'package:pesaclarity/src/features/backup/application/backup_service.dart';
import 'package:pesaclarity/src/features/backup/data/backup_settings_repository.dart';
import 'package:pesaclarity/src/features/backup/data/key_value_store.dart';
import 'package:pesaclarity/src/features/backup/data/vault_client.dart';
import 'package:pesaclarity/src/features/spaces/application/space_manager.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/features/spaces/data/space_files.dart';
import 'package:pesaclarity/src/features/spaces/presentation/manage_spaces_screens.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/fake_app_lock.dart';
import '../../helpers/fake_auth.dart';
import '../../helpers/test_app.dart';
import '../backup/backup_fakes.dart';

/// The vault server, reachable only while [online].
class _Vault {
  var online = false;
  final deleted = <String>[];
  final backups = <Map<String, Object?>>[
    _backup('p1', personalSpaceId, DateTime.utc(2026, 11, 10)),
    _backup('s1', 'shop1', DateTime.utc(2026, 11, 9)),
    _backup('s2', 'shop1', DateTime.utc(2026, 11, 10)),
  ];

  static Map<String, Object?> _backup(String id, String space, DateTime at) => {
    'id': id,
    'space': space,
    'created_at': at.toIso8601String(),
  };

  http.Client client() => MockClient((request) async {
    if (!online) throw const SocketException('Failed host lookup');
    if (request.method == 'GET') {
      return http.Response(jsonEncode(backups), 200);
    }
    final id = request.url.pathSegments.last;
    deleted.add(id);
    backups.removeWhere((b) => b['id'] == id);
    return http.Response('', 204);
  });

  List<Override> get overrides => [
    vaultBaseUrlProvider.overrideWithValue(
      Uri.parse('https://vault.example.test/'),
    ),
    vaultTokenSourceProvider.overrideWithValue(
      SessionVaultTokenSource(
        () async =>
            online ? 'token' : throw const AuthFailure(AuthFailureKind.network),
      ),
    ),
    vaultHttpClientProvider.overrideWithValue(client),
  ];
}

class _Files implements SpaceFiles {
  final deleted = <String>[];
  var erased = false;

  @override
  Future<void> deleteDatabase(String spaceId) async => deleted.add(spaceId);

  @override
  Future<void> eraseEverything() async => erased = true;

  @override
  Future<Directory> keptDirectory() async =>
      Directory.systemTemp.createTemp('kept');
}

class _Restarter implements AppRestarter {
  var restarted = false;

  @override
  Future<void> restart() async => restarted = true;
}

class _NoStore implements ActiveSpaceStore {
  const _NoStore();

  @override
  Future<void> write(String spaceId) async {}

  @override
  Future<void> writeOpenChoice(String choice) async {}
}

/// A server no request reaches.
class _OfflineAuthApi extends FakeAuthApi {
  _OfflineAuthApi() {
    offline = true;
  }
}

const _shop = Space(id: 'shop1', name: 'Mama Mboga', kind: SpaceKind.business);

void main() {
  late AppDatabase db;
  late _Files files;
  late _Vault vault;
  late MemoryKeyValueStore backupStore;
  late FakeDocumentStorage documents;
  late bool reachable;
  late FakeAuthApi authApi;

  setUp(() {
    db = openTestDatabase();
    files = _Files();
    vault = _Vault();
    backupStore = MemoryKeyValueStore();
    documents = FakeDocumentStorage();
    reachable = false;
    authApi = _OfflineAuthApi();
    _restarter = null;
  });

  List<Override> overrides({_Restarter? restarter, bool signedIn = false}) => [
    ...appLockOverrides(),
    appDatabaseProvider.overrideWithValue(db),
    personalDatabaseProvider.overrideWithValue(db),
    activeSpaceIdProvider.overrideWith(ActiveSpaceId.new),
    activeSpaceStoreProvider.overrideWithValue(const _NoStore()),
    clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 11, 9)),
    spaceFilesProvider.overrideWithValue(files),
    backupKeyValueStoreProvider.overrideWithValue(backupStore),
    ...vault.overrides,
    authApiProvider.overrideWithValue(authApi),
    serverReachableProvider.overrideWithValue(() async => reachable),
    sessionStoreProvider.overrideWithValue(
      InMemorySessionStore(
        signedIn
            ? const StoredSession(
                refreshToken: 'refresh-made-up-0001',
                accountId: 'account-test-1',
                deviceId: 'device-test-1',
              )
            : null,
      ),
    ),
    deviceNameSourceProvider.overrideWithValue(const FakeDeviceNameSource()),
    if (restarter != null) appRestarterProvider.overrideWithValue(restarter),
    documentStorageProvider.overrideWithValue(documents),
    backupServiceProvider.overrideWith(
      (ref) => BackupService(
        data: FakeLocalDataStore(List.generate(512, (i) => i % 7)),
        settings: ref.watch(backupSettingsRepositoryProvider),
        workDirectory: () async =>
            Directory.systemTemp.createTempSync('offline-backup'),
        clock: () => DateTime.utc(2026, 11, 11, 9),
        kdfParams: const KdfParams(
          memoryKiB: 256,
          iterations: 1,
          parallelism: 1,
        ),
        runner: <R>(FutureOr<R> Function() work) async => work(),
      ),
    ),
  ];

  Future<void> seed() => DriftAppSettingsRepository(db).writeJson(
    SpacesController.settingsKey,
    spacesToJson([Space.personal, _shop]),
  );

  Future<void> show(
    WidgetTester tester,
    Widget home, {
    bool signedIn = false,
  }) async {
    await tester.runAsync(seed);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(signedIn: signedIn, restarter: _restarter),
        child: MaterialApp(
          theme: AppTheme.light,
          navigatorKey: navigator,
          // The screen it was opened from, where notes show afterwards.
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => home),
      ),
    );
    await settleFrames(tester);
  }

  testAppWidgets('offline, a space is deleted here and its online copy '
      'once online', (tester) async {
    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await seed();
      final later = await container
          .read(spaceManagerProvider)
          .delete(_shop, keep: false, deleteOnline: true);

      expect(later, isTrue);
      expect(files.deleted, ['shop1'], reason: 'deleted on the phone');
      expect(await container.read(spacesProvider.future), [Space.personal]);
      final waiting = await BackupSettingsRepository(backupStore).load();
      expect(waiting.pendingOnlineDeletes.keys, ['shop1']);

      final backups = container.read(backupControllerProvider.notifier);
      await backups.catchUp(); // still offline
      expect(vault.deleted, isEmpty);

      vault.online = true;
      // A copy made after the delete was asked for, from another phone.
      vault.backups.add(
        _Vault._backup('s3', 'shop1', DateTime.utc(2026, 11, 12)),
      );
      await backups.catchUp();
      expect(vault.deleted, unorderedEquals(['s1', 's2']));
      expect(
        (await BackupSettingsRepository(
          backupStore,
        ).load()).pendingOnlineDeletes,
        isEmpty,
      );
    });
  });

  testAppWidgets('online, the online copy goes at once', (tester) async {
    vault.online = true;
    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      await seed();
      final later = await container
          .read(spaceManagerProvider)
          .delete(_shop, keep: false, deleteOnline: true);
      expect(later, isFalse);
      expect(vault.deleted, unorderedEquals(['s1', 's2']));
    });
  });

  testAppWidgets('the Delete space sheet closes offline and says the online '
      'copy follows', (tester) async {
    final repo = BackupSettingsRepository(backupStore);
    await tester.runAsync(() async {
      await repo.writeSecrets(
        BackupSecrets(
          passphrase: 'made-up passphrase for tests',
          recoveryKey: RecoveryKey.generate(),
        ),
      );
      await repo.save(
        const BackupSettings(
          enabled: {BackupLocationId.vault, BackupLocationId.deviceFolder},
          folder: DeviceFolder(uri: 'content://tree/sd', name: 'SD card'),
        ),
      );
    });
    await show(tester, const SpaceSettingsScreen(spaceId: 'shop1'));
    await tester.ensureVisible(find.byKey(const Key('space-delete')));
    await tester.tap(find.byKey(const Key('space-delete')));
    await tester.pumpAndSettle();

    // Back up first, offline: the SD card gets its copy, and the sheet
    // stays usable.
    await tester.tap(find.text('Back up first'));
    for (var i = 0; i < 4; i++) {
      await settleFrames(tester);
    }
    expect(tester.takeException(), isNull);
    expect(documents.written, hasLength(1));
    expect(
      find.text(
        'Backed up to SD card. The vault needs a connection; it will back up '
        'when you are online.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('keep-30-days')));
    await tester.tap(find.byKey(const Key('delete-online')));
    await tester.enterText(
      find.byKey(const Key('space-delete-name')),
      'Mama Mboga',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('space-delete-confirm')));
    await settleFrames(tester);

    expect(tester.takeException(), isNull);
    expect(files.deleted, ['shop1']);
    expect(find.byKey(const Key('space-delete-confirm')), findsNothing);
    expect(
      find.text(
        'Deleted on this phone. The online copy will be deleted when you '
        'are online.',
      ),
      findsOneWidget,
    );
  });

  /// Opens Delete all my data, signed in, ticks [online] and [signIn],
  /// and confirms.
  Future<void> deleteAll(
    WidgetTester tester, {
    bool online = true,
    bool signIn = true,
  }) async {
    _restarter = _Restarter();
    await show(tester, const DeleteAllScreen(), signedIn: true);
    if (online) await tester.tap(find.byKey(const Key('delete-all-online')));
    if (signIn) await tester.tap(find.byKey(const Key('delete-all-sign-in')));
    await tester.enterText(find.byKey(const Key('delete-all-check')), 'DELETE');
    await tester.pump();
    await tester.tap(find.byKey(const Key('delete-all-confirm')));
    await settleFrames(tester);
    expect(tester.takeException(), isNull);
  }

  for (final (online, signIn, title) in [
    (true, true, 'Deleting your online backup and sign-in needs a connection.'),
    (true, false, 'Deleting your online backup needs a connection.'),
    (false, true, 'Deleting your sign-in needs a connection.'),
  ]) {
    testAppWidgets('offline, Delete all my data asks first: $title', (
      tester,
    ) async {
      await deleteAll(tester, online: online, signIn: signIn);
      expect(find.text(title), findsOneWidget);
      expect(files.erased, isFalse, reason: 'nothing before the answer');
    });
  }

  testAppWidgets("Wait until I'm online deletes nothing", (tester) async {
    await deleteAll(tester);
    await tester.tap(find.text("Wait until I'm online"));
    await settleFrames(tester);

    expect(files.erased, isFalse);
    expect(_restarter!.restarted, isFalse);
    expect(authApi.calls, isEmpty);
    expect(find.byType(SnackBar), findsNothing);
    final confirm = tester.widget<FilledButton>(
      find.byKey(const Key('delete-all-confirm')),
    );
    expect(confirm.onPressed, isNotNull, reason: 'can be tried again');
  });

  testAppWidgets('Delete on this phone only erases the phone and skips the '
      'online steps', (tester) async {
    await deleteAll(tester);
    await tester.tap(find.text('Delete on this phone only'));
    await settleFrames(tester);

    expect(files.erased, isTrue);
    expect(_restarter!.restarted, isTrue);
    expect(authApi.calls, isEmpty, reason: 'no online steps');
    expect(vault.deleted, isEmpty);
    expect(find.byType(SnackBar), findsNothing, reason: 'no later-delete note');
  });

  testAppWidgets('online, Delete all my data deletes the online copies and '
      'the sign-in too', (tester) async {
    reachable = true;
    vault.online = true;
    authApi = FakeAuthApi()
      ..knowSession('refresh-made-up-0001', 'device-test-1');
    await deleteAll(tester);

    expect(find.byType(AlertDialog), findsNothing, reason: 'nothing to ask');
    expect(vault.deleted, unorderedEquals(['p1', 's1', 's2']));
    expect(authApi.accountDeleted, isTrue);
    expect(files.erased, isTrue);
    expect(find.byType(SnackBar), findsNothing);
    expect(_restarter!.restarted, isTrue);
  });

  testAppWidgets('online, a step that fails partway is named plainly', (
    tester,
  ) async {
    reachable = true; // The phone has a connection, but the vault fails.
    authApi = FakeAuthApi()
      ..knowSession('refresh-made-up-0001', 'device-test-1');
    await deleteAll(tester);

    expect(files.erased, isTrue);
    expect(authApi.accountDeleted, isTrue);
    expect(
      find.text(
        'Deleted on this phone. Your online backup could not be deleted.',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await settleFrames(tester);
    expect(_restarter!.restarted, isTrue);
  });
}

_Restarter? _restarter;
