import 'package:flutter/material.dart';

import '../../features/security/application/balance_visibility.dart';
import '../../theme/app_typography.dart';
import '../../theme/brand_tokens.dart';
import 'amounts_hidden.dart';

/// Brand-red card that leads a screen with its one primary number. Every
/// red card is this one, so they all look and behave the same.
///
/// Amounts in [figure] and [caption] are masked while balances are hidden,
/// and the card then offers the eye button that shows or hides them.
class HeroFigureCard extends StatelessWidget {
  const HeroFigureCard({
    required this.label,
    required this.figure,
    this.caption,
    this.footer,
    this.onTap,
    this.showEye,
    super.key,
  });

  final String label;
  final String figure;

  /// Lines under the figure, one per entry in the text.
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
    final hasAmount =
        containsAmount(figure) || (caption != null && containsAmount(caption!));

    return Card(
      color: scheme.primary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: textTheme.labelLarge!.copyWith(
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
                  if (showEye ?? hasAmount) AmountsEye(color: scheme.onPrimary),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                maskAmountsIf(hidden, figure),
                style: AppTypography.leadFigure(scheme.onPrimary),
              ),
              if (caption != null) ...[
                const SizedBox(height: 8),
                Text(
                  maskAmountsIf(hidden, caption!),
                  style: textTheme.bodyMedium!.copyWith(
                    color: scheme.onPrimary,
                  ),
                ),
              ],
              if (footer != null) ...[const SizedBox(height: 16), footer!],
            ],
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
