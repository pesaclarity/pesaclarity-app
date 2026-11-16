import 'package:flutter/material.dart';

import '../../features/security/application/balance_visibility.dart';
import '../../theme/app_typography.dart';
import '../../theme/brand_tokens.dart';
import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';
import 'amounts_hidden.dart';

/// The card that leads a screen with its one primary number: a calm
/// surface card, its figure in the theme's display type. Every lead card is
/// this one, so they all look and behave the same. Brand red is kept for
/// actions, so the card is never filled red.
///
/// Amounts in [figure] and [caption] are masked while balances are hidden,
/// and the card then offers the eye button that shows or hides them.
class HeroFigureCard extends StatelessWidget {
  const HeroFigureCard({
    required this.label,
    this.figure,
    this.caption,
    this.footer,
    this.onTap,
    this.showEye,
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

  /// Whether the eye shows; by default, when the card shows an amount.
  final bool? showEye;

  /// Whether the person is below zero: the figure then takes the danger
  /// colour, the one restrained sign of it. Say why in [caption].
  final bool belowZero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colors = PesaColors.of(context);
    final hidden = AmountsHidden.of(context);
    final figure = this.figure;
    final hasAmount =
        (figure != null && containsAmount(figure)) ||
        (caption != null && containsAmount(caption!));
    final eye = showEye ?? hasAmount;
    final figureColor = belowZero ? colors.danger : theme.colorScheme.onSurface;

    return Card(
      child: InkWell(
        onTap: onTap,
        // The card starts at its minimum height and grows with its text.
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: Layout.heroMinHeight,
                minWidth: double.infinity,
              ),
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  Layout.heroPadding,
                  Layout.heroPadding,
                  eye ? Layout.heroEyeSpace : Layout.heroPadding,
                  Layout.heroPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: textTheme.labelLarge!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    if (figure != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        maskAmountsIf(hidden, figure),
                        style: AppTypography.leadFigure(figureColor),
                      ),
                    ],
                    if (caption != null) ...[
                      SizedBox(height: figure == null ? 6 : 8),
                      Text(
                        maskAmountsIf(hidden, caption!.replaceAll('\n', ' · ')),
                        style: textTheme.bodyMedium!.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                    if (footer != null) ...[
                      const SizedBox(height: 12),
                      footer!,
                    ],
                  ],
                ),
              ),
            ),
            if (eye)
              PositionedDirectional(
                top: Layout.heroEyeInset,
                end: Layout.heroEyeInset,
                child: AmountsEye(color: colors.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}

/// A bar on a lead card, such as how much of the month's plan is used,
/// with an optional [label] under it.
class HeroProgress extends StatelessWidget {
  const HeroProgress({required this.value, this.label, super.key});

  /// From 0 to 1.
  final double value;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(BrandTokens.pillRadius),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            // The text colour on a neutral track, as other bars are.
            color: theme.colorScheme.onSurface,
            backgroundColor: colors.border,
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label!,
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}
