import 'package:flutter/material.dart';

import '../../features/security/application/balance_visibility.dart';
import '../../theme/app_typography.dart';
import '../../theme/brand_tokens.dart';
import '../../theme/layout.dart';
import 'amounts_hidden.dart';

/// Brand-red card that leads a screen with its one primary number. Every
/// red card is this one, so they all look and behave the same.
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hidden = AmountsHidden.of(context);
    final figure = this.figure;
    final hasAmount =
        (figure != null && containsAmount(figure)) ||
        (caption != null && containsAmount(caption!));
    final eye = showEye ?? hasAmount;
    // The label and caption are softened so the figure leads.
    const soft = BrandTokens.onBrandSoft;

    return Card(
      color: scheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
      ),
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
                      style: textTheme.labelLarge!.copyWith(color: soft),
                    ),
                    if (figure != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        maskAmountsIf(hidden, figure),
                        style: AppTypography.leadFigure(scheme.onPrimary),
                      ),
                    ],
                    if (caption != null) ...[
                      SizedBox(height: figure == null ? 6 : 8),
                      Text(
                        maskAmountsIf(hidden, caption!.replaceAll('\n', ' · ')),
                        style: textTheme.bodyMedium!.copyWith(color: soft),
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
                child: AmountsEye(color: scheme.onPrimary),
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(BrandTokens.pillRadius),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 8,
            color: scheme.onPrimary,
            backgroundColor: scheme.onPrimary.withValues(alpha: 0.25),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 8),
          Text(
            label!,
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: scheme.onPrimary),
          ),
        ],
      ],
    );
  }
}
