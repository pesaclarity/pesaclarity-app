import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/ask/presentation/ask_entry.dart';
import 'package:pesaclarity/src/features/security/application/balance_visibility.dart';
import 'package:pesaclarity/src/routing/app_shell.dart';
import 'package:pesaclarity/src/shared/accessibility.dart';
import 'package:pesaclarity/src/shared/widgets/amounts_hidden.dart';
import 'package:pesaclarity/src/shared/widgets/app_sheet.dart';
import 'package:pesaclarity/src/shared/widgets/figures.dart';
import 'package:pesaclarity/src/shared/widgets/form_fields.dart';
import 'package:pesaclarity/src/shared/widgets/hero_figure_card.dart';
import 'package:pesaclarity/src/shared/widgets/marks.dart';
import 'package:pesaclarity/src/shared/widgets/states.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';
import 'package:pesaclarity/src/theme/pesa_colors.dart';

import '../helpers/app_fonts.dart';
import '../helpers/test_app.dart';

/// Screen readers (TalkBack, VoiceOver) and the phone's accessibility
/// settings. The screens at large text sizes, with their tap targets and
/// labels, are checked by tool/accessibility.sh.
/// How many lines [text] is drawn on.
int lines(RenderParagraph text) => {
  for (final box in text.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.text.toPlainText().length),
  ))
    box.top.round(),
}.length;

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

  group('at twice the text size on a 390 dp phone', () {
    void twice(WidgetTester tester) {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    void phone(WidgetTester tester, {bool large = true}) {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      if (large) twice(tester);
    }

    // The app's own fonts, so text takes the widths it takes on a phone.
    setUpAll(loadAppFonts);

    testWidgets('every tab label is the same size, and whole', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 80, 20),
              child: PillNavigationBar(
                destinations: personalTabs,
                selectedIndex: 4,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      final labels = [
        for (final d in personalTabs)
          tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.byType(PillNavigationBar),
              matching: find.text(d.label),
            ),
          ),
      ];
      final sizes = {
        for (final l in labels) l.textScaler.scale(11).toStringAsFixed(2),
      };
      expect(sizes, hasLength(1), reason: 'labels drawn at $sizes');
      // Larger than the usual size, and not cut.
      expect(labels.first.textScaler.scale(1), greaterThan(1));
      for (final l in labels) {
        expect(l.didExceedMaxLines, isFalse);
        expect(
          l.size.width + 0.5,
          greaterThanOrEqualTo(l.getMaxIntrinsicWidth(double.infinity)),
        );
      }
    });

    testWidgets('a lead amount keeps its code and number on one line', (
      tester,
    ) async {
      phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(20),
                child: HeroFigureCard(
                  label: 'Safe to spend today · Weekday',
                  figure: 'KES 1,000',
                  showEye: true,
                ),
              ),
            ),
          ),
        ),
      );
      final figure = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(FigureText),
          matching: find.byType(RichText),
        ),
      );
      expect(figure.text.toPlainText(), 'KES 1,000');
      final lines = figure.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 9),
      );
      expect({for (final b in lines) b.top}, hasLength(1));
      // Not shrunk: at least its usual size, and not scrolled out of view.
      expect(figure.textScaler.scale(1), greaterThanOrEqualTo(1));
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('field labels sit above their fields and wrap, read with '
        'them', (tester) async {
      phone(tester);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final label in ['You count it in', 'In stock now'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: LabeledField(
                          label: label,
                          child: const TextField(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      for (final label in ['You count it in', 'In stock now']) {
        final text = tester.renderObject<RenderParagraph>(find.text(label));
        expect(text.didExceedMaxLines, isFalse, reason: label);
        // Too long for one line at twice the size: it wraps, whole.
        expect(lines(text), greaterThan(1));
        // Above its field, and the field reads it as its name.
        final field = find.ancestor(
          of: find.byType(TextField),
          matching: find.byType(LabeledField),
        );
        expect(
          tester.getBottomLeft(find.text(label)).dy,
          lessThanOrEqualTo(
            tester
                .getTopLeft(
                  find
                      .descendant(
                        of: field.at(label == 'You count it in' ? 0 : 1),
                        matching: find.byType(TextField),
                      )
                      .first,
                )
                .dy,
          ),
        );
        expect(
          tester.getSemantics(
            find
                .descendant(
                  of: field.at(label == 'You count it in' ? 0 : 1),
                  matching: find.byType(EditableText),
                )
                .first,
          ),
          isSemantics(label: label, isTextField: true),
        );
      }
      handle.dispose();
    });

    testWidgets('a row name wraps to two lines, then ends in "...", and its '
        'amount stays whole', (tester) async {
      phone(tester);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  for (final name in [
                    'Green Basket',
                    'Green Basket Grocers',
                    'Green Basket Grocers and Butchery, Westlands Branch',
                  ])
                    Row(
                      children: [
                        Expanded(child: RowName(name)),
                        const SizedBox(width: 12),
                        const Text('-1,440'),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      RenderParagraph name(String text) =>
          tester.renderObject<RenderParagraph>(find.text(text));
      expect(lines(name('Green Basket')), 1);
      final two = name('Green Basket Grocers');
      expect(lines(two), 2);
      expect(two.didExceedMaxLines, isFalse);
      final long = name('Green Basket Grocers and Butchery, Westlands Branch');
      expect(lines(long), 2);
      expect(long.didExceedMaxLines, isTrue);
      for (final amount in tester.renderObjectList<RenderParagraph>(
        find.text('-1,440'),
      )) {
        expect(amount.didExceedMaxLines, isFalse);
        expect(
          amount.size.width + 0.5,
          greaterThanOrEqualTo(amount.getMaxIntrinsicWidth(double.infinity)),
        );
        expect(amount.textScaler.scale(1), 2);
      }
    });

    testAppWidgets('Home scrolls clear of the Ask bar', (tester) async {
      phone(tester, large: false);
      await pumpApp(tester, db: openTestDatabase());
      await finishOnboarding(tester);
      twice(tester);
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(
        find
            .descendant(
              of: find.byType(AskBarScope),
              matching: find.byType(ListView),
            )
            .first,
      );
      final bar = tester.getSize(find.byType(AskBar));
      expect(
        list.padding!.resolve(TextDirection.ltr).bottom,
        greaterThanOrEqualTo(bar.height + AskBarScope.margin.vertical),
      );
    });
  });

  group('small muted print', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      test('reads at 4.5:1 or more on the page, cards and sheets in $name', () {
        final colors = theme.extension<PesaColors>()!;
        final small = colors.mutedSmall(theme.colorScheme.onSurface);
        for (final ground in [
          theme.scaffoldBackgroundColor,
          theme.colorScheme.surface,
          colors.floating,
          // A tinted card, such as "The drawer matches the records."
          Color.alphaBlend(colors.successSoft, theme.scaffoldBackgroundColor),
        ]) {
          expect(contrast(small, ground), greaterThanOrEqualTo(4.5));
          // Darker than the usual muted text, lighter than body text.
          expect(
            contrast(small, ground),
            greaterThan(contrast(colors.textMuted, ground)),
          );
          expect(
            contrast(small, ground),
            lessThan(contrast(theme.colorScheme.onSurface, ground)),
          );
        }
      });
    }
  });
}
