import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/shared/widgets/hero_figure_card.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

void main() {
  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    group('$name theme', () {
      Future<void> pump(WidgetTester tester, {bool belowZero = false}) =>
          tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: HeroFigureCard(
                    label: 'All accounts',
                    figure: belowZero ? '-KES 1,150' : 'KES 2,400',
                    belowZero: belowZero,
                  ),
                ),
              ),
            ),
          );

      Color? figureColour(WidgetTester tester, String text) =>
          tester.widget<Text>(find.text(text)).style?.color;

      testWidgets('is the brand-red card with a white figure', (tester) async {
        await pump(tester);
        final card = tester.widget<Card>(find.byType(Card));
        // The same red in light and dark, never a pink.
        expect(card.color, const Color(0xFFC8102E));
        expect(card.color, theme.colorScheme.primary);
        expect(figureColour(tester, 'KES 2,400'), theme.colorScheme.onPrimary);
      });

      testWidgets('below zero, stays red with its minus sign in white', (
        tester,
      ) async {
        await pump(tester, belowZero: true);
        expect(
          tester.widget<Card>(find.byType(Card)).color,
          theme.colorScheme.primary,
        );
        expect(figureColour(tester, '-KES 1,150'), theme.colorScheme.onPrimary);
      });
    });
  }
}
