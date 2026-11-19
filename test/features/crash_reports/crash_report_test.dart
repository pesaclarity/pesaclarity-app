import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/domain/privacy/consent.dart';
import 'package:pesaclarity/src/domain/privacy/privacy_policy.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/app_status/data/app_status_source.dart';
import 'package:pesaclarity/src/features/auth/data/json_transport.dart';
import 'package:pesaclarity/src/features/crash_reports/application/crash_reports.dart';
import 'package:pesaclarity/src/features/crash_reports/data/crash_report_sender.dart';
import 'package:pesaclarity/src/features/crash_reports/data/pending_crash_store.dart';
import 'package:pesaclarity/src/features/crash_reports/domain/crash_report.dart';
import 'package:pesaclarity/src/features/privacy/application/consent_controller.dart';
import 'package:pesaclarity/src/features/privacy/data/policy_source.dart';

import '../app_status/app_status_fakes.dart';

const context = CrashContext(
  app: '0.5.2',
  buildNumber: 412,
  build: 'play',
  os: 'Android 13',
  cpu: 'arm64',
);

/// Synthetic personal data that must never reach a report.
const planted = [
  'Ksh 1,250.00',
  'KES 5,000',
  '+254700000000',
  '0700 000 000',
  'wanjiku@example.com',
  'Wanjiku Kamau',
  'RKT4ABC12X Confirmed. Ksh300.00 sent to OTIENO',
  '/data/user/0/com.pesaclarity.app/files/ledger.db',
];

final obfuscated = StackTrace.fromString('''
*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
pid: 4321, tid: 4400, name 1.ui
os: android arch: arm64 comp: yes sim: no
build_id: 'b6f1c4e09a2d7f35a1c2'
isolate_dso_base: 7a1c000000, vm_dso_base: 7a1c000000
isolate_instructions: 7a1c2b4000, vm_instructions: 7a1c2a0000
    #00 abs 0000007a1c4f8b3c virt 00000000002f4b3c _kDartIsolateSnapshotInstructions+0x244b3c
    #01 abs 0000007a1c4f89e0 virt 00000000002f49e0 _kDartIsolateSnapshotInstructions+0x2449e0
    #02 Wanjiku Kamau paid Ksh 1,250.00
''');

final symbolic = StackTrace.fromString('''
#0      InsightsController._monthTotals (package:pesaclarity/src/features/insights/insights_controller.dart:212:7)
#1      <anonymous closure> (package:riverpod/src/core/element.dart:301:5)
#2      Ksh 1,250.00 to Wanjiku (package:pesaclarity/x.dart:1:1)
#3      main (file:///data/user/0/com.pesaclarity.app/app.dart:3:1)
#4      _RootZone.runUnary (dart:async/zone.dart:1849:19)
''');

PrivacyPolicy policy(String version) => PrivacyPolicy(
  title: 'Privacy policy',
  version: PolicyVersion.parse(version),
  updated: CalendarDate(2026, 11, 19),
  blocks: const [],
);

class FakeSender implements CrashReportSender {
  FakeSender({this.works = true});

  bool works;
  final sent = <CrashReport>[];

  @override
  Future<bool> send(CrashReport report) async {
    if (works) sent.add(report);
    return works;
  }
}

class RecordingTransport implements JsonTransport {
  RecordingTransport([this.status = 202]);

  final int status;
  final requests = <(String, Uri, Object?, Map<String, String>)>[];

  @override
  Future<JsonResponse> send(
    String method,
    Uri url, {
    Object? body,
    String? bearer,
    Map<String, String> headers = const {},
  }) async {
    requests.add((method, url, body, headers));
    return JsonResponse(status);
  }
}

void main() {
  group('the builder', () {
    test('names the error by type, never by its message', () {
      for (final text in planted) {
        for (final error in <Object>[
          StateError(text),
          ArgumentError(text),
          RangeError(text),
          FormatException(text),
          TimeoutException(text),
          FileSystemException(text, text),
          PlatformException(code: text, message: text, details: text),
          Exception(text),
          text,
        ]) {
          final report = buildCrashReport(error, obfuscated, context)!;
          final sent = jsonEncode(report.toJson());
          expect(sent, isNot(contains(text)), reason: '$error');
          expect(CrashReport.errorTypes, contains(report.error));
        }
      }
      expect(
        buildCrashReport(StateError('x'), obfuscated, context)!.error,
        'StateError',
      );
      expect(
        buildCrashReport(RangeError('x'), obfuscated, context)!.error,
        'RangeError',
      );
      expect(
        buildCrashReport(Exception('x'), obfuscated, context)!.error,
        'Other',
      );
    });

    test('reduces an obfuscated stack to offsets and drops other lines', () {
      final report = buildCrashReport(StateError('x'), obfuscated, context)!;
      expect(report.buildId, 'b6f1c4e09a2d7f35a1c2');
      expect(report.stack, ['#00 pc 0x2f4b3c', '#01 pc 0x2f49e0']);
      final sent = jsonEncode(report.toJson());
      for (final text in [...planted, 'pid', '4321', '7a1c']) {
        expect(sent, isNot(contains(text)));
      }
    });

    test('keeps only package: and dart: frames with plain names', () {
      final report = buildCrashReport(StateError('x'), symbolic, context)!;
      expect(report.buildId, isNull);
      expect(report.stack, [
        '#00 InsightsController._monthTotals '
            '(package:pesaclarity/src/features/insights/insights_controller.dart:212:7)',
        '#01 <anonymous closure> (package:riverpod/src/core/element.dart:301:5)',
        '#02 _RootZone.runUnary (dart:async/zone.dart:1849:19)',
      ]);
      final sent = jsonEncode(report.toJson());
      for (final text in planted) {
        expect(sent, isNot(contains(text)));
      }
      expect(sent, isNot(contains('file:')));
    });

    test('has exactly the schema fields, in order', () {
      final report = buildCrashReport(TypeErrorFake(), obfuscated, context)!;
      expect(report.toJson().keys, [
        'format',
        'app',
        'build_number',
        'build',
        'os',
        'cpu',
        'error',
        'build_id',
        'stack',
      ]);
      expect(
        jsonEncode(
          buildCrashReport(StateError('x'), obfuscated, context)!.toJson(),
        ),
        '{"format":1,"app":"0.5.2","build_number":412,"build":"play",'
        '"os":"Android 13","cpu":"arm64","error":"StateError",'
        '"build_id":"b6f1c4e09a2d7f35a1c2",'
        '"stack":["#00 pc 0x2f4b3c","#01 pc 0x2f49e0"]}',
      );
    });

    test('keeps at most 64 frames and 16 KB', () {
      final long = StackTrace.fromString(
        [
          for (var i = 0; i < 200; i++)
            '#$i      a.b (package:pesaclarity/${'d' * 150}.dart:1:1)',
        ].join('\n'),
      );
      final report = buildCrashReport(StateError('x'), long, context)!;
      expect(report.stack.length, lessThanOrEqualTo(CrashReport.maxFrames));
      expect(
        utf8.encode(jsonEncode(report.toJson())).length,
        lessThanOrEqualTo(CrashReport.maxBytes),
      );
    });

    test('names nothing it cannot: no report for an unknown phone', () {
      const bad = CrashContext(
        app: '0.5.2',
        buildNumber: 1,
        build: 'play',
        os: 'Android 13 (samsung/a52/a52q)',
        cpu: 'arm64',
      );
      expect(buildCrashReport(StateError('x'), obfuscated, bad), isNull);
    });

    test('reads back only valid reports', () {
      final report = buildCrashReport(StateError('x'), obfuscated, context)!;
      expect(CrashReport.fromJson(report.toJson())!.toJson(), report.toJson());
      expect(
        CrashReport.fromJson({...report.toJson(), 'error': 'Ksh 5'}),
        isNull,
      );
      expect(CrashReport.fromJson({...report.toJson(), 'format': 2}), isNull);
      expect(
        CrashReport.fromJson({
          ...report.toJson(),
          'stack': ['#00 pc 0x1', 'wanjiku@example.com'],
        }),
        isNull,
      );
    });
  });

  test('cpu names come from the ABI', () {
    expect(cpuName(Abi.androidArm64), 'arm64');
    expect(cpuName(Abi.androidArm), 'arm');
    expect(cpuName(Abi.iosArm64), 'arm64');
    expect(cpuName(Abi.windowsX64), isNull);
  });

  test('capture keeps at most three built reports', () async {
    final store = MemoryPendingCrashStore();
    final capture = CrashCapture(store: store, context: context);
    for (var i = 0; i < 5; i++) {
      await capture.record(StateError(planted.first), obfuscated);
    }
    expect(store.reports, hasLength(PendingCrashStore.maxPending));
    expect(
      jsonEncode([for (final r in store.reports) r.toJson()]),
      isNot(contains('Ksh')),
    );
  });

  group('on start', () {
    late MemorySettings settings;
    late MemoryPendingCrashStore store;
    late FakeSender sender;

    setUp(() async {
      settings = MemorySettings();
      store = MemoryPendingCrashStore();
      sender = FakeSender();
      await store.add(buildCrashReport(StateError('x'), obfuscated, context)!);
    });

    Future<ProviderContainer> container({
      String accepted = '2.4',
      bool oldSwitch = false,
      CrashReportChoice? choice,
    }) async {
      await settings.writeJson(
        ConsentController.recordKey,
        const ConsentRecord()
            .accept(
              PolicyVersion.parse(accepted),
              at: testNow,
              values: {ConsentKind.crashReports: oldSwitch},
            )
            .toJson(),
      );
      final c = ProviderContainer(
        overrides: [
          mainSettingsRepositoryProvider.overrideWithValue(settings),
          pendingCrashStoreProvider.overrideWithValue(store),
          crashReportSenderProvider.overrideWithValue(sender),
          privacyPolicyProvider.overrideWithValue(AsyncData(policy(accepted))),
          clockProvider.overrideWithValue(() => testNow),
        ],
      );
      addTearDown(c.dispose);
      if (choice != null) {
        await c.read(crashReportChoiceProvider.notifier).choose(choice);
      }
      return c;
    }

    test('Ask each time is the default and waits for the sheet', () async {
      final c = await container();
      expect(
        await c.read(crashReportChoiceProvider.future),
        CrashReportChoice.ask,
      );
      expect(
        await c.read(pendingCrashReportsProvider.future),
        PendingOutcome.waitingForAnswer,
      );
      expect(sender.sent, isEmpty);
      expect(store.reports, hasLength(1));
    });

    test('the old switch on becomes Always send', () async {
      final c = await container(oldSwitch: true);
      expect(
        await c.read(crashReportChoiceProvider.future),
        CrashReportChoice.always,
      );
      expect(
        await c.read(pendingCrashReportsProvider.future),
        PendingOutcome.sent,
      );
      expect(sender.sent, hasLength(1));
      expect(store.reports, isEmpty);
    });

    test('Never send deletes them', () async {
      final c = await container(choice: CrashReportChoice.never);
      expect(store.reports, isEmpty);
      expect(
        await c.read(pendingCrashReportsProvider.future),
        PendingOutcome.none,
      );
      expect(sender.sent, isEmpty);
    });

    test('nothing is sent before policy 2.4', () async {
      final c = await container(
        accepted: '2.3',
        choice: CrashReportChoice.always,
      );
      expect(
        await c.read(pendingCrashReportsProvider.future),
        PendingOutcome.notYet,
      );
      expect(sender.sent, isEmpty);
    });

    test('offline: they wait for the next start', () async {
      sender.works = false;
      final c = await container(choice: CrashReportChoice.always);
      expect(
        await c.read(pendingCrashReportsProvider.future),
        PendingOutcome.notYet,
      );
      expect(store.reports, hasLength(1));
    });
  });

  test('the sender posts exactly the report, with no token or id', () async {
    final transport = RecordingTransport();
    final sender = HttpCrashReportSender(
      baseUrl: Uri.parse('https://api.example.org'),
      transport: transport,
    );
    final report = buildCrashReport(StateError('x'), obfuscated, context)!;
    expect(await sender.send(report), isTrue);
    final (method, url, body, headers) = transport.requests.single;
    expect(method, 'POST');
    expect(url.toString(), 'https://api.example.org/v1/crash-reports');
    expect(body, report.toJson());
    expect(headers, isEmpty);
  });

  test(
    'app status puts the counting token in a header, never the URL',
    () async {
      final transport = RecordingTransport(200);
      final source = HttpAppStatusSource(
        baseUrl: Uri.parse('https://api.example.org'),
        transport: transport,
      );
      await source.fetch(
        version: '0.5.2',
        build: 'play',
        platform: 'android',
        countToken: 'AAAAAAAAAAAAAAAAAAAAAA',
      );
      await source.fetch(version: '0.5.2', build: 'play', platform: 'android');
      final (_, url, _, headers) = transport.requests.first;
      expect(headers, {countTokenHeader: 'AAAAAAAAAAAAAAAAAAAAAA'});
      expect(url.toString(), isNot(contains('AAAAAAAAAAAAAAAAAAAAAA')));
      expect(transport.requests.last.$4, isEmpty);
    },
  );
}

/// A [TypeError] the way the runtime raises one.
class TypeErrorFake extends TypeError {}
