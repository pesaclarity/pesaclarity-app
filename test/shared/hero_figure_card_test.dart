import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/shared/widgets/hero_figure_card.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';
import 'package:pesaclarity/src/theme/pesa_colors.dart';

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

      testWidgets('is a calm surface card, never a red fill', (tester) async {
        await pump(tester);
        final card = tester.widget<Card>(find.byType(Card));
        // The theme's card: surface colour, bordered, no fill of its own.
        expect(card.color, isNull);
        expect(theme.cardTheme.color, theme.colorScheme.surface);
        expect(figureColour(tester, 'KES 2,400'), theme.colorScheme.onSurface);
      });

      testWidgets('below zero, only the figure takes the danger colour', (
        tester,
      ) async {
        await pump(tester, belowZero: true);
        expect(tester.widget<Card>(find.byType(Card)).color, isNull);
        expect(
          figureColour(tester, '-KES 1,150'),
          theme.extension<PesaColors>()!.danger,
        );
      });
    });
  }
}
