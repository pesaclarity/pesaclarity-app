import 'package:flutter/material.dart';

import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';

/// A debt in a list: the lender, what is left, a bar of how much is paid,
/// and a line under it. The same on Goals and on Debts.
class DebtRow extends StatelessWidget {
  const DebtRow({
    required this.name,
    required this.amount,
    required this.paidFraction,
    required this.caption,
    this.captionColor,
    this.onTap,
    super.key,
  });

  final String name;

  /// What is left, already formatted and masked while amounts are hidden.
  final String amount;

  /// From 0 to 1.
  final double paidFraction;
  final String caption;

  /// The caption's colour; muted by default.
  final Color? captionColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Layout.cardPadding,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: theme.textTheme.bodyLarge)),
                const SizedBox(width: 12),
                Text(
                  amount,
                  style: AppTypography.rowAmount(theme.colorScheme.onSurface),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: paidFraction,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              color: theme.colorScheme.primary,
              backgroundColor: colors.border,
              semanticsLabel: '${(paidFraction * 100).floor()}% paid',
            ),
            const SizedBox(height: 8),
            Text(
              caption,
              style: theme.textTheme.bodySmall!.copyWith(
                color: captionColor ?? colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
