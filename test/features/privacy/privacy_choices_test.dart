import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/domain/privacy/consent.dart';
import 'package:pesaclarity/src/domain/privacy/privacy_policy.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/app_status/application/update_check_choice.dart';
import 'package:pesaclarity/src/features/counting/application/counting.dart';
import 'package:pesaclarity/src/features/counting/data/count_token_store.dart';
import 'package:pesaclarity/src/features/crash_reports/application/crash_reports.dart';
import 'package:pesaclarity/src/features/crash_reports/data/pending_crash_store.dart';
import 'package:pesaclarity/src/features/crash_reports/presentation/crash_choice_sheet.dart';
import 'package:pesaclarity/src/features/privacy/application/consent_controller.dart';
import 'package:pesaclarity/src/features/privacy/data/policy_source.dart';
import 'package:pesaclarity/src/features/privacy/presentation/privacy_choices_card.dart';
import 'package:pesaclarity/src/features/privacy/presentation/privacy_screen.dart';
import 'package:pesaclarity/src/features/privacy/presentation/privacy_widgets.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../app_status/app_status_fakes.dart';

PrivacyPolicy policy(String version) => PrivacyPolicy(
  title: 'Privacy policy',
  version: PolicyVersion.parse(version),
  updated: CalendarDate(2026, 11, 19),
  blocks: const [],
);

void main() {
  late MemorySettings settings;

  setUp(() => settings = MemorySettings());

  Future<void> pumpPrivacy(
    WidgetTester tester, {
    String agreed = '2.4',
    AppFlavor flavor = AppFlavor.play,
    double textScale = 1,
  }) async {
    await tester.runAsync(
      () => settings.writeJson(
        ConsentController.recordKey,
        const ConsentRecord()
            .accept(PolicyVersion.parse(agreed), at: testNow, values: const {})
            .toJson(),
      ),
    );
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final overrides = <Override>[
      mainSettingsRepositoryProvider.overrideWithValue(settings),
      privacyPolicyProvider.overrideWithValue(AsyncData(policy(agreed))),
      appFlavorProvider.overrideWithValue(flavor),
      clockProvider.overrideWithValue(() => testNow),
      countTokenStoreProvider.overrideWithValue(MemoryCountTokenStore()),
      pendingCrashStoreProvider.overrideWithValue(MemoryPendingCrashStore()),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(theme: AppTheme.light, home: const PrivacyScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  CheckboxListTile box(WidgetTester tester, String title) =>
      tester.widget<CheckboxListTile>(
        find.ancestor(
          of: find.text(title),
          matching: find.byType(CheckboxListTile),
        ),
      );

  Future<void> tap(WidgetTester tester, String text) async {
    if (find.text(text).evaluate().isEmpty) {
      // Privacy's list builds rows as they scroll into view.
      await tester.scrollUntilVisible(
        find.text(text),
        200,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await tester.ensureVisible(find.text(text));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('before policy 2.4: the choices as they were', (tester) async {
    await pumpPrivacy(tester, agreed: '2.3');
    expect(find.byType(PrivacyChoicesCard), findsNothing);
    expect(find.text('Send crash reports'), findsOneWidget);
    expect(find.text(PrivacyPromisesCard.promises[1]), findsOneWidget);
    expect(find.text(PrivacyRowLabels.counting.$1), findsNothing);
    // The new wording for Help improve the app is true already.
    expect(
      find.text('Learn from your corrections on this phone. Nothing is sent'),
      findsOneWidget,
    );
  });

  testWidgets('after 2.4, Play: counting on, crash reports ask each time', (
    tester,
  ) async {
    await pumpPrivacy(tester);
    expect(find.text(PrivacyPromisesCard.countsPromise), findsOneWidget);
    expect(find.text('Send crash reports'), findsNothing);
    expect(find.text(PrivacyRowLabels.updateCheck.$1), findsNothing);
    await tester.ensureVisible(find.text(PrivacyRowLabels.counting.$1));
    expect(box(tester, PrivacyRowLabels.counting.$1).value, isTrue);
    expect(find.text('Ask each time'), findsOneWidget);

    await tap(tester, PrivacyRowLabels.counting.$1);
    expect(box(tester, PrivacyRowLabels.counting.$1).value, isFalse);
    expect(settings.values[CountingController.settingsKey]!['value'], isFalse);

    await tap(tester, PrivacyRowLabels.crashReports);
    expect(find.text(CrashChoiceSheet.title), findsWidgets);
    await tester.tap(find.text('Never send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CrashChoiceSheet.done));
    await tester.pumpAndSettle();
    expect(
      settings.values[CrashReportChoiceController.settingsKey]!['value'],
      'never',
    );
    expect(find.text('Never send'), findsOneWidget);
  });

  testWidgets('a crash choice is kept only on Done', (tester) async {
    await pumpPrivacy(tester);
    await tap(tester, PrivacyRowLabels.crashReports);
    await tester.tap(find.text('Always send'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(settings.values[CrashReportChoiceController.settingsKey], isNull);
    expect(find.text('Ask each time'), findsOneWidget);
  });

  testWidgets('after 2.4, F-Droid: the update check and counting start off', (
    tester,
  ) async {
    await pumpPrivacy(tester, flavor: AppFlavor.foss);
    await tester.ensureVisible(find.text(PrivacyRowLabels.updateCheck.$1));
    expect(box(tester, PrivacyRowLabels.updateCheck.$1).value, isFalse);
    expect(box(tester, PrivacyRowLabels.counting.$1).value, isFalse);
    await tap(tester, PrivacyRowLabels.updateCheck.$1);
    expect(
      settings.values[UpdateCheckChoiceController.settingsKey]!['value'],
      isTrue,
    );
    expect(box(tester, PrivacyRowLabels.updateCheck.$1).value, isTrue);
  });

  testWidgets('works at twice the text size', (tester) async {
    await pumpPrivacy(tester, flavor: AppFlavor.foss, textScale: 2);
    expect(tester.takeException(), isNull);
    await tap(tester, PrivacyRowLabels.crashReports);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text(CrashChoiceSheet.done));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Always send'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(CrashChoiceSheet.done));
    await tester.pumpAndSettle();
    await tester.tap(find.text(CrashChoiceSheet.done));
    await tester.pumpAndSettle();
    expect(
      settings.values[CrashReportChoiceController.settingsKey]!['value'],
      'always',
    );
  });
}
