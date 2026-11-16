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

  /// Whether the person is below zero. On the red card the figure stays
  /// white and its minus sign shows it; say why in [caption].
  final bool belowZero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final hidden = AmountsHidden.of(context);
    final figure = this.figure;
    final hasAmount =
        (figure != null && containsAmount(figure)) ||
        (caption != null && containsAmount(caption!));
    final eye = showEye ?? hasAmount;
    final scheme = theme.colorScheme;
    final onCard = scheme.onPrimary;
    final figureColor = onCard;

    return Card(
      color: scheme.primary,
      child: InkWell(
        onTap: onTap,
        // The card starts at its minimum height and grows with its text.
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final shown = figure == null
                    ? null
                    : maskAmountsIf(hidden, figure);
                final figureStyle = AppTypography.leadFigure(figureColor);
                // The eye keeps its corner clear. A figure too wide to
                // sit beside it takes the card's full width on a line
                // below the eye, rather than splitting.
                final underEye =
                    eye &&
                    shown != null &&
                    FigureText.numberWidth(context, shown, figureStyle) >
                        constraints.maxWidth -
                            Layout.heroPadding -
                            Layout.heroEyeSpace;
                final besideEye = eye && !underEye;
                final labelText = Text(
                  label,
                  style: textTheme.labelLarge!.copyWith(color: onCard),
                );
                return ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: Layout.heroMinHeight,
                    minWidth: double.infinity,
                  ),
                  child: Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(
                      Layout.heroPadding,
                      Layout.heroPadding,
                      besideEye ? Layout.heroEyeSpace : Layout.heroPadding,
                      Layout.heroPadding,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (underEye)
                          ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight:
                                  Layout.heroEyeInset +
                                  Layout.minTouch -
                                  Layout.heroPadding,
                            ),
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(
                                end: Layout.heroEyeSpace - Layout.heroPadding,
                              ),
                              child: labelText,
                            ),
                          )
                        else
                          labelText,
                        if (shown != null) ...[
                          const SizedBox(height: 4),
                          FigureText(shown, style: figureStyle),
                        ],
                        if (caption != null) ...[
                          SizedBox(height: figure == null ? 6 : 8),
                          Text(
                            maskAmountsIf(
                              hidden,
                              caption!.replaceAll('\n', ' · '),
                            ),
                            style: textTheme.bodyMedium!.copyWith(
                              color: onCard,
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
                );
              },
            ),
            if (eye)
              PositionedDirectional(
                top: Layout.heroEyeInset,
                end: Layout.heroEyeInset,
                child: AmountsEye(color: onCard),
              ),
          ],
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
            backgroundColor: onCard.withValues(alpha: 0.25),
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
