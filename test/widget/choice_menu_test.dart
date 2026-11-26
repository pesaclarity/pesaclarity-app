import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/shared/widgets/choice_menu.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';
import 'package:pesaclarity/src/theme/pesa_colors.dart';

/// A filter pill that is narrowing what shows: a solid red pill, or, as the
/// chosen side of a switch is, the plain pill with its label in red.
void main() {
  final themes = {
    'light': AppTheme.light,
    'dark': AppTheme.dark,
    'light high contrast': AppTheme.lightHighContrast,
    'dark high contrast': AppTheme.darkHighContrast,
  };

  Future<void> pump(
    WidgetTester tester,
    ThemeData theme, {
    required bool highlight,
    ChoiceHighlight highlightAs = ChoiceHighlight.fill,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: Center(
          child: ChoiceMenu<int>(
            key: const Key('menu'),
            options: const [(0, 'All'), (1, 'Paid')],
            value: highlight ? 1 : 0,
            highlight: highlight,
            highlightAs: highlightAs,
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );

  Material pill(WidgetTester tester) => tester.widget<Material>(
    find
        .descendant(
          of: find.byKey(const Key('menu')),
          matching: find.byType(Material),
        )
        .first,
  );

  TextStyle label(WidgetTester tester, String text) => tester
      .renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(const Key('menu')),
          matching: find.text(text),
        ),
      )
      .text
      .style!;

  Color arrow(WidgetTester tester) =>
      tester.widget<Icon>(find.byIcon(Icons.arrow_drop_down)).color!;

  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    final colors = theme.extension<PesaColors>()!;
    final scheme = theme.colorScheme;

    testWidgets('$name: a narrowing filter as text is red on the plain pill', (
      tester,
    ) async {
      await pump(tester, theme, highlight: false);
      final plain = pill(tester);
      final plainLabel = label(tester, 'All');
      expect(plain.color, colors.field);
      expect((plain.shape! as StadiumBorder).side.color, colors.border);
      expect(plainLabel.color, scheme.onSurface);
      expect(arrow(tester), scheme.onSurface);

      await pump(
        tester,
        theme,
        highlight: true,
        highlightAs: ChoiceHighlight.text,
      );
      final chosen = pill(tester);
      final chosenLabel = label(tester, 'Paid');
      // No fill and no new edge: the same pill as when it is not narrowing.
      expect(chosen.color, plain.color);
      expect(chosen.shape, plain.shape);
      // Only the label and its arrow turn red; the weight stays as it is.
      expect(chosenLabel.color, colors.link);
      expect(chosenLabel.fontWeight, plainLabel.fontWeight);
      expect(chosenLabel.fontSize, plainLabel.fontSize);
      expect(arrow(tester), colors.link);
      // Red text reads at 4.5:1 on the pill.
      expect(contrast(colors.link, chosen.color!), greaterThanOrEqualTo(4.5));
    });

    testWidgets('$name: a narrowing filter as a fill is still a red pill', (
      tester,
    ) async {
      await pump(tester, theme, highlight: true);
      expect(pill(tester).color, scheme.primary);
      expect(label(tester, 'Paid').color, scheme.onPrimary);
    });
  }
}
