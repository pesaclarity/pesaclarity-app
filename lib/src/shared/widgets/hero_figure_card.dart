import 'package:flutter/material.dart';

import '../../features/security/application/balance_visibility.dart';
import '../../theme/app_typography.dart';
import '../../theme/brand_tokens.dart';
import '../../theme/layout.dart';
import 'amounts_hidden.dart';
import 'figures.dart';

/// Brand-red card that leads a screen with its one primary number, in
/// white. Every red card is this one, so they all look and behave the
/// same. In dark it keeps the same red, never a pink.
///
/// Amounts in [figure] and [caption] are masked while balances are hidden.
/// The eye that shows or hides them is never on the card: it sits last in
/// the screen's header or app bar.
class HeroFigureCard extends StatelessWidget {
  const HeroFigureCard({
    required this.label,
    this.figure,
    this.caption,
    this.footer,
    this.onTap,
    this.belowZero = false,
    super.key,
  });

  final String label;

  /// The one number; null while there is nothing to count yet, and then
  /// [caption] says what will show and when, in its place.
  final String? figure;

  /// A line under the figure; line breaks in the text show as " · ".
  final String? caption;

  /// Below the caption, such as a [HeroProgress] bar. Mask its amounts
  /// yourself.
  final Widget? footer;
  final VoidCallback? onTap;

  /// Whether the person is below zero. On the red card the figure stays
  /// white and its minus sign shows it; say why in [caption].
  final bool belowZero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final hidden = AmountsHidden.of(context);
    final figure = this.figure;
    final scheme = theme.colorScheme;
    final onCard = scheme.onPrimary;
    final figureColor = onCard;
    final shown = figure == null ? null : maskAmountsIf(hidden, figure);
    final figureStyle = AppTypography.leadFigure(figureColor);

    return Card(
      color: scheme.primary,
      child: InkWell(
        onTap: onTap,
        // The card starts at its minimum height and grows with its text.
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: Layout.heroMinHeight,
            minWidth: double.infinity,
          ),
          child: Padding(
            padding: const EdgeInsets.all(Layout.heroPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: textTheme.labelLarge!.copyWith(color: onCard),
                ),
                if (shown != null) ...[
                  const SizedBox(height: 4),
                  _LeadFigure(shown, style: figureStyle),
                ],
                if (caption != null) ...[
                  SizedBox(height: figure == null ? 6 : 8),
                  Text(
                    maskAmountsIf(hidden, caption!.replaceAll('\n', ' · ')),
                    style: textTheme.bodyMedium!.copyWith(color: onCard),
                  ),
                ],
                if (footer != null) ...[const SizedBox(height: 12), footer!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A bar on a red card, such as how much of the month's plan is used, with
/// an optional [label] under it.
class HeroProgress extends StatelessWidget {
  const HeroProgress({required this.value, this.label, super.key});

  /// From 0 to 1.
  final double value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onCard = theme.colorScheme.onPrimary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(BrandTokens.pillRadius),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            color: onCard,
            backgroundColor: _track,
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label!,
            style: theme.textTheme.bodyMedium!.copyWith(color: onCard),
          ),
        ],
      ],
    );
  }
}

/// The empty part of a bar on the red card: brand red one step deeper, an
/// opaque colour (as the card has always drawn it) rather than a shade
/// laid over the card.
const _track = Color(0xFFA00D25);

/// The card's figure on one line, or, when it is too wide for the card (as
/// at large text), its currency code on the line above the number, so the
/// number shows whole rather than fading at the card's edge. One text, so
/// it reads as one amount.
class _LeadFigure extends StatelessWidget {
  const _LeadFigure(this.value, {required this.style});

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final space = value.lastIndexOf(' ');
      if (space < 0 ||
          FigureText.numberWidth(context, value, style) <=
              constraints.maxWidth ||
          FigureText.numberWidth(context, value.substring(space + 1), style) >
              constraints.maxWidth) {
        return FigureText(value, style: style);
      }
      return readAsAmount(
        value,
        Text(value, style: style, textScaler: figureTextScaler(context, style)),
      );
    },
  );
}
