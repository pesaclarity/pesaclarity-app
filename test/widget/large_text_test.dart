import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/shared/widgets/figures.dart';
import 'package:pesaclarity/src/shared/widgets/hero_figure_card.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../helpers/test_app.dart';

/// Large text from the phone's settings: cards grow and money moves to a
/// line of its own, never split, with nothing overflowing. An overflow
/// reports a Flutter error, which fails the test.
void main() {
  for (final scale in [1.3, 2.0]) {
    testAppWidgets('Home fits at ${scale}x text', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);

      await pumpApp(tester, db: openTestDatabase());
      await finishOnboarding(tester);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tiles and the lead card grow at ${scale}x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
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
                  children: const [
                    HeroFigureCard(
                      label: 'Safe to spend today',
                      figure: 'KES 1,234,567,890',
                      caption: 'For the next 7 days\n12,345,678 on hand',
                    ),
                    SizedBox(height: 12),
                    FigureRow(
                      children: [
                        FigureTile(
                          label: 'On hand',
                          value: 'KES 12,345,678,901',
                        ),
                        FigureTile(
                          label: 'Runway at this pace',
                          value: 'Today',
                          note: 'Shows after two weeks of records',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Money is shown whole, never shrunk or cut.
      expect(find.text('KES 12,345,678,901'), findsOneWidget);
      // Too long to sit two to a row whole, so each tile takes a row.
      final tiles = find.byType(FigureTile);
      expect(
        tester.getRect(tiles.last).top,
        greaterThan(tester.getRect(tiles.first).bottom),
      );
      expect(
        tester.getSize(tiles.first).width,
        tester.getSize(tiles.last).width,
      );
    });
  }
}
