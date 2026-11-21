import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/domain/privacy/consent.dart';
import 'package:pesaclarity/src/domain/privacy/privacy_policy.dart';
import 'package:pesaclarity/src/features/crash_reports/application/crash_reports.dart';
import 'package:pesaclarity/src/features/crash_reports/data/crash_report_sender.dart';
import 'package:pesaclarity/src/features/crash_reports/data/pending_crash_store.dart';
import 'package:pesaclarity/src/features/crash_reports/domain/crash_report.dart';
import 'package:pesaclarity/src/features/crash_reports/presentation/crash_report_sheet.dart';
import 'package:pesaclarity/src/features/privacy/application/consent_controller.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../app_status/app_status_fakes.dart';

const report = CrashReport(
  app: '0.5.2',
  buildNumber: 412,
  build: 'play',
  os: 'Android 13',
  cpu: 'arm64',
  error: 'TypeError',
  buildId: 'b6f1c4e09a2d7f35',
  stack: ['#00 pc 0x2f4b3c', '#01 pc 0x2f49e0'],
);

class FakeSender implements CrashReportSender {
  final sent = <CrashReport>[];

  /// Whether the server can be reached.
  var online = true;

  @override
  Future<bool> send(CrashReport report) async {
    if (online) sent.add(report);
    return online;
  }
}

void main() {
  late MemorySettings settings;
  late MemoryPendingCrashStore store;
  late FakeSender sender;

  setUp(() {
    settings = MemorySettings();
    store = MemoryPendingCrashStore()..reports.add(report);
    sender = FakeSender();
  });

  Future<void> open(WidgetTester tester, {double textScale = 1}) async {
    await tester.runAsync(
      () => settings.writeJson(
        ConsentController.recordKey,
        const ConsentRecord()
            .accept(PolicyVersion.parse('2.4'), at: testNow, values: const {})
            .toJson(),
      ),
    );
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mainSettingsRepositoryProvider.overrideWithValue(settings),
          pendingCrashStoreProvider.overrideWithValue(store),
          crashReportSenderProvider.overrideWithValue(sender),
          clockProvider.overrideWithValue(() => testNow),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showCrashReportSheet(context, [report]),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('shows exactly what would be sent', (tester) async {
    await open(tester);
    for (final text in [
      CrashReportSheet.title,
      CrashReportSheet.body,
      CrashReportSheet.seeTitle,
      CrashReportSheet.seeSubtitle,
      CrashReportSheet.sameTitle,
      CrashReportSheet.sameSubtitle,
      CrashReportSheet.send,
      CrashReportSheet.dontSend,
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.text(report.preview), findsNothing);
    await tap(tester, CrashReportSheet.seeTitle);
    expect(find.text(report.preview), findsOneWidget);
    expect(find.text(CrashReportSheet.stackNote), findsOneWidget);
    expect(
      tester.getSemantics(find.text(CrashReportSheet.title)),
      isSemantics(isHeader: true),
    );
  });

  testWidgets('Send report sends it; Do the same makes it Always send', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, CrashReportSheet.sameTitle);
    await tap(tester, CrashReportSheet.send);
    expect(sender.sent, [report]);
    expect(store.reports, isEmpty);
    expect(
      settings.values[CrashReportChoiceController.settingsKey]!['value'],
      'always',
    );
    expect(find.text(CrashReportSheet.title), findsNothing);
  });

  testWidgets('Send report offline sends it later without asking again', (
    tester,
  ) async {
    sender.online = false;
    await open(tester);
    await tap(tester, CrashReportSheet.send);
    expect(find.text(CrashReportSheet.title), findsNothing);
    expect(store.reports, isEmpty, reason: 'not asked about again');
    expect(store.toSend, [report]);
    expect(settings.values[CrashReportChoiceController.settingsKey], isNull);
  });

  testWidgets("Don't send deletes it; Do the same makes it Never send", (
    tester,
  ) async {
    await open(tester);
    await tap(tester, CrashReportSheet.sameTitle);
    await tap(tester, CrashReportSheet.dontSend);
    expect(sender.sent, isEmpty);
    expect(store.reports, isEmpty);
    expect(
      settings.values[CrashReportChoiceController.settingsKey]!['value'],
      'never',
    );
  });

  testWidgets("Don't send alone keeps Ask each time", (tester) async {
    await open(tester);
    await tap(tester, CrashReportSheet.dontSend);
    expect(store.reports, isEmpty);
    expect(settings.values[CrashReportChoiceController.settingsKey], isNull);
  });

  testWidgets('works at twice the text size', (tester) async {
    await open(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    await tap(tester, CrashReportSheet.seeTitle);
    expect(tester.takeException(), isNull);
    await tap(tester, CrashReportSheet.send);
    expect(sender.sent, [report]);
  });
}
