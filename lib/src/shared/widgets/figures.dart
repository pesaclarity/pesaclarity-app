import 'package:flutter/material.dart';

import '../../theme/app_typography.dart';
import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';

/// A small card with one figure under its label, such as "Stock value" or
/// "Running low". Put two or three side by side with [FigureRow].
class FigureTile extends StatelessWidget {
  const FigureTile({
    required this.label,
    required this.value,
    this.note,
    this.onTap,
    super.key,
  });

  final String label;

  /// Already formatted, and masked while amounts are hidden.
  final String value;

  /// A short line under the figure.
  final String? note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  value,
                  style: AppTypography.tileFigure(theme.colorScheme.onSurface),
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 4),
                Text(note!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiles side by side, the same height, [Layout.cardGap] apart.
class FigureRow extends StatelessWidget {
  const FigureRow({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(width: Layout.cardGap),
          Expanded(child: child),
        ],
      ],
    ),
  );
}

/// A row with a name, an optional [detail] under it, and a [value] at the
/// end, such as a line on an invoice or in the tax estimate.
class LabelValueRow extends StatelessWidget {
  const LabelValueRow({
    required this.label,
    required this.value,
    this.detail,
    this.strong = false,
    this.onTap,
    super.key,
  });

  final String label;
  final String? detail;

  /// Already formatted, and masked while amounts are hidden.
  final String value;

  /// A total: the label in bold.
  final bool strong;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.cardPadding,
        vertical: 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: strong
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.bodyLarge,
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: AppTypography.rowAmount(theme.colorScheme.onSurface),
          ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}
