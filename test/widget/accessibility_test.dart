import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/security/application/balance_visibility.dart';
import 'package:pesaclarity/src/shared/accessibility.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';
import 'package:pesaclarity/src/shared/widgets/app_sheet.dart';
import 'package:pesaclarity/src/shared/widgets/figures.dart';
import 'package:pesaclarity/src/shared/widgets/states.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';

/// Screen readers (TalkBack, VoiceOver) and the phone's accessibility
/// settings. The screens at large text sizes, with their tap targets and
/// labels, are checked by tool/accessibility.sh.
void main() {
  Widget app(Widget child, {bool hidden = false}) => ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light,
      home: AmountsHidden(
        hidden: hidden,
        child: Scaffold(body: child),
      ),
    ),
  );

  group('amounts read aloud', () {
    test('say minus and hidden, never dots', () {
      expect(spokenAmounts('-KES 1,200'), 'minus KES 1,200');
      expect(spokenAmounts('-950'), 'minus 950');
      expect(spokenAmounts('Balance -USD 25.00'), 'Balance minus USD 25.00');
      expect(spokenAmounts('KES $maskedDigits'), 'KES hidden');
      expect(spokenAmounts(maskedDigits), 'hidden');
      // A dash between words is not a sign.
      expect(spokenAmounts('M-Pesa 1,200'), 'M-Pesa 1,200');
    });

    testWidgets('a figure reads its amount', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          FigureText(
            '-KES 1,200',
            style: Theme.of(tester.binding.rootElement!).textTheme.bodyLarge!,
          ),
        ),
      );
      expect(find.bySemanticsLabel('minus KES 1,200'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a hidden figure reads as hidden, with no digits', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => FigureTile(
              label: 'On hand',
              value: shownMoney(context, 123456),
            ),
          ),
          hidden: true,
        ),
      );
      final label = tester
          .getSemantics(find.byType(FigureTile))
          .getSemanticsData()
          .label;
      expect(label, contains('hidden'));
      expect(label, isNot(contains(RegExp(r'\d'))));
      expect(label, isNot(contains('•')));
      handle.dispose();
    });
  });

  testWidgets('a sheet title is a header', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      app(const SheetBody(title: 'Add a goal', children: [Text('Body')])),
    );
    expect(
      tester.getSemantics(find.text('Add a goal')),
      isSemantics(label: 'Add a goal', isHeader: true),
    );
    handle.dispose();
  });

  testWidgets('a short message is announced', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showNote(context, 'Sale saved.'),
            child: const Text('Save'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.semantics.byPredicate(
        (node) =>
            node.getSemanticsData().flagsCollection.isLiveRegion &&
            node.getSemanticsData().label.contains('Sale saved.'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('an error that replaces a screen is announced', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      app(ErrorView('Your goals could not load.', onRetry: () {})),
    );
    expect(
      tester.getSemantics(find.text('Your goals could not load.')),
      isSemantics(label: 'Your goals could not load.', isLiveRegion: true),
    );
    handle.dispose();
  });

  group('less motion', () {
    Future<void> open(WidgetTester tester, {required bool reduce}) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduce);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) =>
              Theme(data: withReducedMotion(Theme.of(context)), child: child!),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Next')),
                ),
              ),
              child: const Text('Go'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
    }

    /// The page transition's zoom and fade around the new screen.
    Finder transitions() => find.ancestor(
      of: find.text('Next'),
      matching: find.byWidgetPredicate(
        (w) => w is ScaleTransition || w is FadeTransition,
      ),
    );

    testWidgets('a new screen shows at once', (tester) async {
      await open(tester, reduce: true);
      expect(find.text('Next'), findsOneWidget);
      expect(transitions(), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('a new screen zooms in as usual otherwise', (tester) async {
      await open(tester, reduce: false);
      expect(find.text('Next'), findsOneWidget);
      expect(transitions(), findsWidgets);
      await tester.pumpAndSettle();
    });

    testWidgets('durations drop to none', (tester) async {
      late Duration reduced;
      late Duration usual;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              reduced = motionDuration(context, const Duration(seconds: 1));
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Builder(
            builder: (context) {
              usual = motionDuration(context, const Duration(seconds: 1));
              return const SizedBox();
            },
          ),
        ),
      );
      expect(reduced, Duration.zero);
      expect(usual, const Duration(seconds: 1));
    });
  });

  testAppWidgets('Home has labelled, big enough tap targets', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, db: openTestDatabase());
    await finishOnboarding(tester);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    handle.dispose();
  });
}
