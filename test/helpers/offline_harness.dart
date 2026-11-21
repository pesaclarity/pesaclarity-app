import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:pesaclarity/src/app.dart';
import 'package:pesaclarity/src/config/build_info.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/config/server_config.dart';
import 'package:pesaclarity/src/core/backup/backup.dart';
import 'package:pesaclarity/src/core/network/pinned_http_client.dart';
import 'package:pesaclarity/src/core/network/reachability.dart';
import 'package:pesaclarity/src/core/network/trusted_roots.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/connection.dart';
import 'package:pesaclarity/src/data/database/database_key_store.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/app_status/application/app_status_providers.dart';
import 'package:pesaclarity/src/features/auth/application/auth_controller.dart';
import 'package:pesaclarity/src/features/auth/data/session_store.dart';
import 'package:pesaclarity/src/features/auth/domain/auth_models.dart';
import 'package:pesaclarity/src/features/backup/application/backup_providers.dart';
import 'package:pesaclarity/src/features/backup/application/backup_service.dart';
import 'package:pesaclarity/src/features/backup/data/key_value_store.dart';
import 'package:pesaclarity/src/features/counting/data/count_token_store.dart';
import 'package:pesaclarity/src/features/crash_reports/application/crash_reports.dart';
import 'package:pesaclarity/src/features/crash_reports/data/pending_crash_store.dart';
import 'package:pesaclarity/src/features/crash_reports/domain/crash_report.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/currency/data/rates_client.dart';
import 'package:pesaclarity/src/features/privacy/data/policy_source.dart';
import 'package:pesaclarity/src/features/reminders/data/reminder_notifications.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';
import 'package:pesaclarity/src/features/sms/application/sms_capture_providers.dart';
import 'package:pesaclarity/src/features/sms/application/sms_ingestor.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/features/spaces/data/space_files.dart';
import 'package:pesaclarity/src/features/statements/application/statement_importer.dart';
import 'package:pesaclarity/src/shared/widgets/states.dart';

import '../features/backup/backup_fakes.dart';
import 'app_fonts.dart';
import 'fake_app_lock.dart';
import 'fake_auth.dart';
import 'fake_reminders.dart';
import 'fake_sms_source.dart';
import 'test_app.dart';

/// Boots the real app on a phone with no network: every request fails as a
/// DNS lookup does in airplane mode. It keeps what the person would see,
/// each request the app tried, and every uncaught error, so tests can say
/// that nothing broke.

/// What one run saw: steps, requests and uncaught errors, for failure
/// messages.
class OfflineLog {
  final lines = <String>[];
  final requests = <String>[];
  final uncaught = <Object>[];

  /// Set OFFLINE_LOG=1 to follow a run as it goes.
  static final _echo = Platform.environment['OFFLINE_LOG'] == '1';

  void add(String line) {
    lines.add(line);
    if (_echo) debugPrint(line);
  }

  @override
  String toString() => lines.join('\n');
}

/// An HttpClient with no network.
class OfflineHttpClient implements HttpClient {
  OfflineHttpClient(this.log);

  final OfflineLog log;

  Future<HttpClientRequest> _fail(String method, Uri url) async {
    log
      ..requests.add('$method ${url.host}${url.path}')
      ..add('  request $method ${url.host}${url.path}');
    throw SocketException(
      "Failed host lookup: '${url.host}'",
      osError: const OSError('No address associated with hostname', 7),
    );
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _fail(method, url);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => _fail('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => _fail('POST', url);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => _fail('PUT', url);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _fail('DELETE', url);
  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _fail(method, Uri(scheme: 'https', host: host, port: port, path: path));
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OfflineFactory extends HttpClientFactory {
  _OfflineFactory(this.log) : super(TrustedRoots.none);

  final OfflineLog log;

  @override
  HttpClient create() => OfflineHttpClient(log);

  @override
  HttpClient createUnpinned() => OfflineHttpClient(log);
}

class _OfflineOverrides extends HttpOverrides {
  _OfflineOverrides(this.log);

  final OfflineLog log;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      OfflineHttpClient(log);
}

/// The phone's state that survives a restart of the app.
class OfflinePhone {
  OfflinePhone() {
    final dir = Directory.systemTemp.createTempSync('offline-phone');
    final key = generateDatabaseKey();
    AppDatabase open(String name) => AppDatabase(
      NativeDatabase(
        File('${dir.path}/$name.sqlite'),
        setup: (db) => applyCipherKey(db, key),
      ),
    );
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    personal = open('personal');
    business = open('business');
    addTearDown(() async {
      await personal.close();
      await business.close();
      dir.deleteSync(recursive: true);
    });
  }

  final log = OfflineLog();
  late final AppDatabase personal;
  late final AppDatabase business;
  final secure = MemorySecureStore();
  final sessions = InMemorySessionStore();
  final backupStore = MemoryKeyValueStore();
  final crashes = MemoryPendingCrashStore();
  final counting = MemoryCountTokenStore();
  final documents = FakeDocumentStorage();
  final sms = FakeSmsSource();
  final files = OfflineSpaceFiles();
  var now = DateTime(2026, 11, 21, 8, 5);
  String activeSpace = personalSpaceId;

  /// What the phone's crash capture would keep from an uncaught error.
  Future<void> capture(Object error) => CrashCapture(
    store: crashes,
    context: crashContext,
  ).record(error, StackTrace.current);

  static const crashContext = CrashContext(
    app: '0.5.2',
    buildNumber: 7,
    build: 'play',
    os: 'Android 14',
    cpu: 'arm64',
  );
}

class _SpaceStore implements ActiveSpaceStore {
  const _SpaceStore(this.phone);

  final OfflinePhone phone;

  @override
  Future<void> write(String spaceId) async => phone.activeSpace = spaceId;

  @override
  Future<void> writeOpenChoice(String choice) async {}
}

/// Space files in memory: what was deleted is recorded.
class OfflineSpaceFiles implements SpaceFiles {
  final deleted = <String>[];

  @override
  Future<void> deleteDatabase(String spaceId) async => deleted.add(spaceId);

  @override
  Future<void> eraseEverything() async {}

  @override
  Future<Directory> keptDirectory() async =>
      Directory.systemTemp.createTemp('kept');
}

/// Answers the app's own platform channels as a phone with nothing special
/// would, Google sign-in failing as it does offline.
void mockOfflineChannels(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  for (final name in [
    'com.pesaclarity.app/device',
    'com.pesaclarity.app/google_sign_in',
    'com.pesaclarity.app/app_attest',
    'com.pesaclarity.app/device_integrity',
    'com.pesaclarity.app/screen_capture',
    'com.pesaclarity.app/share',
    'com.pesaclarity.app/printer',
    'com.pesaclarity.app/documents',
  ]) {
    messenger.setMockMethodCallHandler(
      MethodChannel(name),
      (call) async => switch (call.method) {
        'systemVersion' => '14',
        'check' => <String, Object?>{},
        'isCharging' => false,
        'requestIdToken' => throw PlatformException(code: 'failed'),
        _ => null,
      },
    );
  }
}

List<Override> _overrides(OfflinePhone phone, {required bool vault}) => [
  ...appLockOverrides(store: phone.secure),
  appFlavorProvider.overrideWithValue(AppFlavor.play),
  clockProvider.overrideWithValue(() => phone.now),
  // Real encrypted databases, one file per space.
  personalDatabaseProvider.overrideWithValue(phone.personal),
  appDatabaseProvider.overrideWith(
    (ref) => ref.watch(activeSpaceIdProvider) == personalSpaceId
        ? phone.personal
        : phone.business,
  ),
  activeSpaceIdProvider.overrideWith(() => ActiveSpaceId(phone.activeSpace)),
  activeSpaceStoreProvider.overrideWithValue(_SpaceStore(phone)),
  spaceFilesProvider.overrideWithValue(phone.files),
  smsSourceProvider.overrideWithValue(phone.sms),
  smsParseBatchProvider.overrideWithValue(
    (packs, messages) async => parseAll(packs, messages),
  ),
  statementReadBatchProvider.overrideWithValue(
    (pages) async => readStatement(pages),
  ),
  reminderNotificationsProvider.overrideWithValue(FakeReminderNotifications()),
  policyMailerProvider.overrideWithValue(FakePolicyMailer()),
  privacyPolicyProvider.overrideWithValue(AsyncData(bundledPolicy())),
  deviceRegionProvider.overrideWithValue('KE'),
  // Auth: the real controller and HTTP API, with no network.
  sessionStoreProvider.overrideWithValue(phone.sessions),
  deviceNameSourceProvider.overrideWithValue(const FakeDeviceNameSource()),
  serverBaseUrlProvider.overrideWithValue(
    Uri.parse('https://api.pesaclarity.test'),
  ),
  httpClientFactoryProvider.overrideWithValue(_OfflineFactory(phone.log)),
  serverReachableProvider.overrideWithValue(() async => false),
  // A build with a version and a pinned app-status key, so the check runs.
  buildVersionProvider.overrideWithValue('0.5.2'),
  appStatusPublicKeysProvider.overrideWithValue([
    'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY=',
  ]),
  // A build with a rates service.
  ratesConfiguredProvider.overrideWithValue(true),
  ratesClientProvider.overrideWith(
    (ref) => HttpRatesClient(
      template: 'https://rates.example.test/latest/{base}',
      client: IOClient(OfflineHttpClient(phone.log)),
      now: () => phone.now,
    ),
  ),
  // Backups: the vault configured; on-phone stores in memory.
  if (vault)
    vaultBaseUrlProvider.overrideWithValue(
      Uri.parse('https://vault.pesaclarity.test/'),
    ),
  backupKeyValueStoreProvider.overrideWithValue(phone.backupStore),
  documentStorageProvider.overrideWithValue(phone.documents),
  localDataStoreProvider.overrideWithValue(
    FakeLocalDataStore(List.generate(512, (i) => i % 7)),
  ),
  // path_provider and isolates are not in widget tests: a temp folder, a
  // cheap key derivation, and work on the test thread.
  backupServiceProvider.overrideWith(
    (ref) => BackupService(
      data: FakeLocalDataStore(List.generate(512, (i) => i % 7)),
      settings: ref.watch(backupSettingsRepositoryProvider),
      workDirectory: () async =>
          Directory.systemTemp.createTempSync('offline-backup'),
      clock: () => phone.now,
      kdfParams: const KdfParams(memoryKiB: 256, iterations: 1, parallelism: 1),
      runner: <R>(FutureOr<R> Function() work) async => work(),
    ),
  ),
  // Crash capture on, as on a phone (it needs a version and an OS name).
  pendingCrashStoreProvider.overrideWithValue(phone.crashes),
  crashContextProvider.overrideWith((ref) async => OfflinePhone.crashContext),
  countTokenStoreProvider.overrideWithValue(phone.counting),
];

var _fontsLoaded = false;

/// Loads the app's fonts once, so text is measured as on a phone.
Future<void> loadOfflineFonts() async {
  if (_fontsLoaded) return;
  await loadAppFonts();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  _fontsLoaded = true;
}

/// A phone-sized screen.
void offlinePhoneView(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Starts the app as from the launcher, with no network.
Future<void> coldStartOffline(
  WidgetTester tester,
  OfflinePhone phone, {
  bool vault = true,
}) async {
  HttpOverrides.global = _OfflineOverrides(phone.log);
  addTearDown(() => HttpOverrides.global = null);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: _overrides(phone, vault: vault),
      child: const PesaClarityApp(),
    ),
  );
  await settleOffline(tester, phone);
}

/// Lets frames and real async work run. An uncaught error is kept in the
/// log and saved as the phone's crash capture would.
Future<void> settleOffline(WidgetTester tester, OfflinePhone phone) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 20),
    );
  } on FlutterError {
    phone.log.add('  (the screen kept animating for 20 s)');
  }
  final error = tester.takeException();
  if (error != null) {
    phone.log
      ..uncaught.add(error as Object)
      ..add('  UNCAUGHT ${error.runtimeType}: $error');
    await tester.runAsync(() => phone.capture(error));
  }
}

String _texts(Finder of) => find
    .descendant(of: of.first, matching: find.byType(Text))
    .evaluate()
    .map((e) => (e.widget as Text).data ?? '')
    .where((t) => t.trim().isNotEmpty)
    .join(' | ');

/// What is on screen after a step.
final class OfflineScreen {
  const OfflineScreen({
    required this.notes,
    required this.errors,
    required this.sheets,
    required this.spinners,
  });

  /// Snack bar notes, by their text.
  final List<String> notes;

  /// Error views, by their text.
  final List<String> errors;

  /// Bottom sheets and dialogs, by their text.
  final List<String> sheets;

  /// Spinners still turning after the screen settled.
  final int spinners;

  /// Nothing about being offline is in the way.
  bool get calm =>
      notes.isEmpty && errors.isEmpty && sheets.isEmpty && spinners == 0;

  @override
  String toString() =>
      'notes: $notes, errors: $errors, sheets: $sheets, spinners: $spinners';
}

/// Records [name] in the log and returns what is on screen.
OfflineScreen observeOffline(OfflinePhone phone, String name) {
  List<String> all(Type type) => [
    for (final e in find.byType(type).evaluate())
      _texts(find.byElementPredicate((x) => x == e)),
  ];
  final screen = OfflineScreen(
    notes: all(SnackBar),
    errors: all(ErrorView),
    sheets: [...all(BottomSheet), ...all(AlertDialog), ...all(Dialog)],
    spinners: find
        .byType(CircularProgressIndicator)
        .hitTestable()
        .evaluate()
        .length,
  );
  phone.log.add('STEP $name: $screen');
  return screen;
}

/// The stored session of a person who signed in yesterday: a refresh token,
/// and no access token in memory (it lives only in RAM).
const signedInYesterday = StoredSession(
  refreshToken: 'refresh-made-up-0001',
  accountId: 'account-test-1',
  deviceId: 'device-test-1',
  method: SignInMethod.email,
  contact: 'wanjiru@example.com',
  displayName: 'Wanjiru',
);
