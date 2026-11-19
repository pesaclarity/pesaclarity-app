import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/domain/privacy/consent.dart';
import 'package:pesaclarity/src/domain/privacy/privacy_policy.dart';
import 'package:pesaclarity/src/features/app_status/application/app_status_providers.dart';
import 'package:pesaclarity/src/features/app_status/application/update_check_choice.dart';
import 'package:pesaclarity/src/features/app_status/presentation/update_check_sheet.dart';
import 'package:pesaclarity/src/features/counting/application/counting.dart';
import 'package:pesaclarity/src/features/privacy/application/consent_controller.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import 'app_status_fakes.dart';

Future<void> agree(MemorySettings settings, String version) =>
    settings.writeJson(
      ConsentController.recordKey,
      const ConsentRecord()
          .accept(PolicyVersion.parse(version), at: testNow, values: const {})
          .toJson(),
    );

void main() {
  late String publicKey;
  late MemorySettings settings;
  late FakeAppStatusSource source;

  setUpAll(() async => publicKey = await publicKeyOf(testSeed));

  setUp(() async {
    settings = MemorySettings();
    source = FakeAppStatusSource(await signed(payload(build: 'foss')));
  });

  ProviderContainer container({
    AppFlavor flavor = AppFlavor.foss,
    String policy = '2.4',
  }) {
    final c = ProviderContainer(
      overrides: appStatusOverrides(
        source: source,
        publicKey: publicKey,
        settings: settings,
        flavor: flavor,
        policyVersion: policy,
      ),
    );
    addTearDown(c.dispose);
    return c;
  }

  group('who is asked', () {
    test('the F-Droid build, once 2.4 is agreed, until it answers', () async {
      await agree(settings, '2.4');
      final c = container();
      expect(await c.read(updateCheckQuestionProvider.future), isTrue);
      expect(await c.read(updateCheckAllowedProvider.future), isFalse);
      await c.read(updateCheckChoiceProvider.notifier).answer(true);
      expect(await c.read(updateCheckQuestionProvider.future), isFalse);
      expect(await c.read(updateCheckAllowedProvider.future), isTrue);
    });

    test('never other builds', () async {
      await agree(settings, '2.4');
      for (final flavor in [AppFlavor.play, AppFlavor.appstore]) {
        final c = container(flavor: flavor);
        expect(await c.read(updateCheckQuestionProvider.future), isFalse);
        expect(await c.read(updateCheckAllowedProvider.future), isTrue);
      }
    });

    test('before 2.4 the F-Droid check runs as it always has', () async {
      await agree(settings, '2.3');
      final c = container(policy: '2.3');
      expect(await c.read(updateCheckQuestionProvider.future), isFalse);
      expect(await c.read(updateCheckAllowedProvider.future), isTrue);
    });
  });

  group('the update check', () {
    test('sends nothing on F-Droid until "Check daily"', () async {
      await agree(settings, '2.4');
      var c = container();
      expect(await c.read(appStatusProvider.future), isNull);
      expect(source.asked, isEmpty);

      await c.read(updateCheckChoiceProvider.notifier).answer(false);
      c = container();
      expect(await c.read(appStatusProvider.future), isNull);
      expect(source.asked, isEmpty);

      await c.read(updateCheckChoiceProvider.notifier).answer(true);
      c = container();
      expect(await c.read(appStatusProvider.future), isNotNull);
      expect(source.asked, hasLength(1));
      // Counting stays off in the F-Droid build unless ticked.
      expect(source.countTokens.single, isNull);
    });
  });

  group('the sheet', () {
    Future<ProviderContainer> open(
      WidgetTester tester, {
      double textScale = 1,
    }) async {
      await agree(settings, '2.4');
      final c = container();
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showUpdateCheckSheet(context),
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
      return c;
    }

    testWidgets('says what the mockup says', (tester) async {
      await open(tester);
      for (final text in [
        UpdateCheckSheet.title,
        UpdateCheckSheet.body,
        UpdateCheckSheet.countTitle,
        UpdateCheckSheet.countSubtitle,
        UpdateCheckSheet.yes,
        UpdateCheckSheet.no,
        UpdateCheckSheet.footer,
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      final box = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(box.value, isFalse);
      expect(
        tester.getSemantics(find.text(UpdateCheckSheet.title)),
        isSemantics(isHeader: true),
      );
    });

    testWidgets('"Check daily" with the box ticked turns both on', (
      tester,
    ) async {
      final c = await open(tester);
      await tester.tap(find.text(UpdateCheckSheet.countTitle));
      await tester.pump();
      await tester.tap(find.text(UpdateCheckSheet.yes));
      await tester.pumpAndSettle();
      expect(find.text(UpdateCheckSheet.title), findsNothing);
      expect(
        settings.values[UpdateCheckChoiceController.settingsKey]!['value'],
        isTrue,
      );
      expect(settings.values[CountingController.settingsKey]!['value'], isTrue);
      expect(c.read(countingControllerProvider).value, isTrue);
    });

    testWidgets('"Check daily" without the box leaves counting off', (
      tester,
    ) async {
      await open(tester);
      await tester.tap(find.text(UpdateCheckSheet.yes));
      await tester.pumpAndSettle();
      expect(
        settings.values[UpdateCheckChoiceController.settingsKey]!['value'],
        isTrue,
      );
      expect(settings.values[CountingController.settingsKey], isNull);
    });

    testWidgets('"Not now" sends nothing and saves the answer', (tester) async {
      await open(tester);
      await tester.tap(find.text(UpdateCheckSheet.countTitle));
      await tester.pump();
      await tester.tap(find.text(UpdateCheckSheet.no));
      await tester.pumpAndSettle();
      expect(
        settings.values[UpdateCheckChoiceController.settingsKey]!['value'],
        isFalse,
      );
      expect(settings.values[CountingController.settingsKey], isNull);
      expect(source.asked, isEmpty);
    });

    testWidgets('works at twice the text size', (tester) async {
      await open(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text(UpdateCheckSheet.no));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final button in [UpdateCheckSheet.yes, UpdateCheckSheet.no]) {
        final size = tester.getSize(
          find.ancestor(
            of: find.text(button),
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ),
        );
        expect(size.height, greaterThanOrEqualTo(48), reason: button);
      }
      await tester.tap(find.text(UpdateCheckSheet.no));
      await tester.pumpAndSettle();
      expect(
        settings.values[UpdateCheckChoiceController.settingsKey]!['value'],
        isFalse,
      );
    });
  });
}
