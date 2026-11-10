import 'package:flutter/material.dart';

import '../../theme/layout.dart';
import '../../theme/pesa_colors.dart';

/// What a [Tag] or [Notice] is about, which sets its colour.
enum Tone {
  /// Plain information.
  info,

  /// Good news, such as a payment that matched.
  success,

  /// Something to check, such as an item running low.
  warning,
}

/// A small tag beside a name: "Running low", "Service", "Paid".
class Tag extends StatelessWidget {
  const Tag(this.text, {this.tone = Tone.info, super.key});

  final String text;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    final (fill, ink) = switch (tone) {
      Tone.info => (colors.border, colors.textMuted),
      Tone.success => (colors.successSoft, colors.successText),
      Tone.warning => (colors.warningSoft, colors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Layout.tagRadius),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall!.copyWith(color: ink),
      ),
    );
  }
}

/// A short note in a tinted box, such as "Each one matches on its own when
/// the message comes."
class Notice extends StatelessWidget {
  const Notice(this.text, {this.tone = Tone.info, this.icon, super.key});

  final String text;
  final Tone tone;

  /// Shown before the text.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final (fill, edge, ink) = switch (tone) {
      Tone.info => (theme.colorScheme.surface, colors.border, colors.textMuted),
      Tone.success => (
        colors.successSoft,
        colors.success.withValues(alpha: 0.25),
        colors.successText,
      ),
      Tone.warning => (
        colors.warningSoft,
        colors.warning.withValues(alpha: 0.25),
        colors.warning,
      ),
    };
    return Container(
      padding: const EdgeInsets.all(Layout.cardPadding),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(Layout.panelRadius),
        border: Border.all(color: edge),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: ink),
            const SizedBox(width: 12),
          ],
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// A row's leading icon in a soft square, such as on Home's cards.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.brandSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 22, color: colors.link),
    );
  }
}

/// An action word at the end of a row, such as "Edit" or "Change", in the
/// same style as a text button.
class TrailingLink extends StatelessWidget {
  const TrailingLink(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelLarge!
        .copyWith(color: PesaColors.of(context).link),
  );
}

/// A round outlined button for − and +, or for the previous and next month.
class StepButton extends StatelessWidget {
  const StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon),
    style: IconButton.styleFrom(
      side: BorderSide(color: PesaColors.of(context).border),
    ),
  );
}

/// Two buttons side by side: the main one first, the other after it,
/// sharing the width.
class ButtonPair extends StatelessWidget {
  const ButtonPair({required this.primary, required this.secondary, super.key});

  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: primary),
      const SizedBox(width: Layout.cardGap),
      Expanded(child: secondary),
    ],
  );
}
