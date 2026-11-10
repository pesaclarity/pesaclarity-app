import 'package:flutter/material.dart';

import '../../features/security/application/balance_visibility.dart';
import '../../theme/app_typography.dart';
import 'amounts_hidden.dart';

/// Brand-red card that leads a screen with its one primary number.
///
/// Amounts in [figure] and [caption] are masked while balances are hidden,
/// and the card then offers the eye button that shows or hides them.
class HeroFigureCard extends StatelessWidget {
  const HeroFigureCard({
    required this.label,
    required this.figure,
    this.caption,
    super.key,
  });

  final String label;
  final String figure;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hidden = AmountsHidden.of(context);
    final hasAmount =
        containsAmount(figure) || (caption != null && containsAmount(caption!));

    return Card(
      color: scheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                if (hasAmount) AmountsEye(color: scheme.onPrimary),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              maskAmountsIf(hidden, figure),
              style: AppTypography.amount(size: 40, color: scheme.onPrimary),
            ),
            if (caption != null) ...[
              const SizedBox(height: 8),
              Text(
                maskAmountsIf(hidden, caption!),
                style: textTheme.bodyMedium!.copyWith(color: scheme.onPrimary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
