import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/shared/widgets/figures.dart';
import 'package:pesaclarity/src/shared/widgets/hero_figure_card.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';
import 'package:pesaclarity/src/theme/app_typography.dart';

import '../helpers/app_fonts.dart';

/// Amounts are laid out whole: never split across lines, shrunk or cut,
/// at a narrow and a usual phone width and at large text. The real fonts
/// are loaded, so widths are the ones a phone sees.
void main() {
  setUpAll(loadAppFonts);

  // Synthetic balances, up to the longest the app is checked with.
  const figures = ['24,330.50', '102,865', '9,999,999.99'];
  const coded = 'KES 9,999,999.99';

  test('no line break opportunity inside a number', () {
    for (final number in [...figures, '-24,330.50']) {
      final painter = TextPainter(
        text: TextSpan(
          text: number,
          style: AppTypography.tileFigure(Colors.black),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(
        painter.minIntrinsicWidth,
        moreOrLessEquals(painter.width, epsilon: 0.01),
        reason: '$number has no place to break',
      );
      painter.dispose();
    }
  });

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      final at = '${width.toInt()} dp, ${scale}x text';

      Future<void> pump(WidgetTester tester, List<Widget> children) async {
        tester.view.physicalSize = Size(width, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light,
              home: MediaQuery.withClampedTextScaling(
                minScaleFactor: scale,
                maxScaleFactor: scale,
                child: Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.all(20),
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'no overflow at $at');
      }

      testWidgets('Money tiles keep each balance whole at $at', (tester) async {
        await pump(tester, [
          for (final figure in figures) ...[
            FigureRow(
              children: [
                FigureTile(label: 'Cash', value: figure),
                const FigureTile(label: 'M-Pesa', value: '1,200'),
                const FigureTile(label: 'Bank', value: '40,000'),
              ],
            ),
            const SizedBox(height: 12),
          ],
          const FigureRow(
            children: [
              FigureTile(label: 'On hand', value: coded),
              FigureTile(label: 'Left this month', value: '-102,865'),
            ],
          ),
        ]);
        for (final figure in [...figures, coded, '-102,865']) {
          _expectWhole(tester, figure, within: FigureTile);
        }
      });

      testWidgets('rows and the lead card keep amounts whole at $at', (
        tester,
      ) async {
        await pump(tester, [
          for (final figure in figures)
            LabelValueRow(
              label: 'Should be in the drawer',
              detail: 'Start 1,200 + in 350 − out 250',
              value: figure,
            ),
          const HeroFigureCard(label: 'Sales today', figure: 'KES 102,865'),
          const HeroFigureCard(label: 'Sales today', figure: 'KES 24,330.50'),
        ]);
        for (final figure in figures) {
          _expectWhole(tester, figure, within: LabelValueRow);
        }
        _expectWhole(tester, 'KES 102,865', within: HeroFigureCard);
        _expectWhole(tester, 'KES 24,330.50', within: HeroFigureCard);
      });
    }
  }

  testWidgets('tiles that fit stay side by side, the same height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: const [
              FigureRow(
                children: [
                  FigureTile(label: 'On hand', value: '1,200'),
                  FigureTile(
                    label: 'Runway at this pace',
                    value: 'Soon',
                    note: 'Shows after two weeks of records',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final first = tester.getRect(find.byType(FigureTile).first);
    final second = tester.getRect(find.byType(FigureTile).last);
    expect(first.top, second.top);
    expect(first.height, second.height);
    expect(first.width, second.width);
  });

  testWidgets('a figure that does not fit sends the tiles one to a row', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: const [
              FigureRow(
                children: [
                  FigureTile(label: 'Cash', value: '24,330.50'),
                  FigureTile(label: 'M-Pesa', value: '102,865'),
                  FigureTile(label: 'Bank', value: '1,200'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    final tiles = find.byType(FigureTile);
    final rects = [for (var i = 0; i < 3; i++) tester.getRect(tiles.at(i))];
    for (final rect in rects) {
      expect(rect.width, 350, reason: 'each tile takes the full width');
    }
    expect(rects[1].top, greaterThan(rects[0].bottom));
    expect(rects[2].top, greaterThan(rects[1].bottom));
  });
}

/// [value] is drawn with its number on one line, not cut by its own box,
/// and inside the card of type [within]. Where no line on the screen is
/// wide enough, it scrolls sideways, so all of it can still be seen.
void _expectWhole(WidgetTester tester, String value, {required Type within}) {
  final finder = find.text(value);
  expect(finder, findsOneWidget, reason: value);
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final start = value.lastIndexOf(' ') + 1;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: start, extentOffset: value.length),
  );
  expect(
    boxes.map((b) => b.top).toSet(),
    hasLength(1),
    reason: '$value is on one line',
  );
  final right = boxes.map((b) => b.right).reduce((a, b) => a > b ? a : b);
  expect(
    right,
    lessThanOrEqualTo(paragraph.size.width + 0.5),
    reason: '$value is not cut by its own box',
  );

  final scroll = find.ancestor(
    of: finder,
    matching: find.byType(SingleChildScrollView),
  );
  final card = tester.getRect(
    find.ancestor(of: finder, matching: find.byType(within)).first,
  );
  if (scroll.evaluate().isEmpty) {
    final rect = tester.getRect(finder);
    expect(
      card.contains(rect.topLeft) &&
          card.contains(rect.bottomRight - const Offset(0.01, 0.01)),
      isTrue,
      reason: '$value sits inside its card',
    );
  } else {
    // Only where it cannot fit any line: it scrolls, whole.
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: scroll, matching: find.byType(Scrollable)),
        )
        .position;
    expect(
      position.maxScrollExtent + position.viewportDimension,
      moreOrLessEquals(paragraph.size.width, epsilon: 0.5),
      reason: 'all of $value can be scrolled into view',
    );
    expect(tester.getRect(scroll).right, lessThanOrEqualTo(card.right));
  }
}
