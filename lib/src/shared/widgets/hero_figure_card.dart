import 'package:flutter/material.dart';

import '../../theme/app_typography.dart';

/// Brand-red card that leads a screen with its one primary number.
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

    return Card(
      color: scheme.primary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: textTheme.labelLarge!.copyWith(color: scheme.onPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              figure,
              style: AppTypography.amount(size: 40, color: scheme.onPrimary),
            ),
            if (caption != null) ...[
              const SizedBox(height: 8),
              Text(
                caption!,
                style: textTheme.bodyMedium!.copyWith(color: scheme.onPrimary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
