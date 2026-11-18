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
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
        color: colors.border,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        size: 22,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

/// A name's initials in a square the size and shape of an [IconBadge]:
/// neutral, as an Activity row's are, or [tinted] with the brand, as an
/// account's letter on Balances is.
class InitialsBadge extends StatelessWidget {
  const InitialsBadge(this.text, {this.tinted = false, super.key});

  final String text;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tinted ? colors.brandSoft : colors.border,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge!.copyWith(
          color: tinted ? colors.link : Theme.of(context).colorScheme.onSurface,
        ),
      ),
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
        .copyWith(color: Theme.of(context).colorScheme.onSurface),
  );
}

/// A small outlined pill for an action beside a title, in a row or under a
/// card: "Count stock", "See all", "Remind". Neutral, so red stays for the
/// lead card, the main button and the current tab.
class PillButton extends StatelessWidget {
  const PillButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.tooltip,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Says what it does when [label] alone is short, such as "Add a debt".
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: EdgeInsets.fromLTRB(icon == null ? 14 : 10, 0, 14, 0),
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );
    final button = icon == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: Text(label))
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 18),
            label: Text(label),
          );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// "+ Add", at the right of the title of the list it adds to: the screen's
/// title for a screen's list, the section's title for a section. [tooltip]
/// says what it adds, such as "Add a debt".
class AddButton extends StatelessWidget {
  const AddButton({required this.onPressed, required this.tooltip, super.key});

  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => PillButton(
    label: 'Add',
    icon: Icons.add,
    tooltip: tooltip,
    onPressed: onPressed,
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

/// The name at the head of an Activity or Money row, such as a payee: a
/// long one wraps to a second line before it ends in "...", so it stays
/// readable at larger text. The row's amount beside it is never shortened.
class RowName extends StatelessWidget {
  const RowName(this.name, {this.style, super.key});

  final String name;
  final TextStyle? style;

  static const maxLines = 2;

  @override
  Widget build(BuildContext context) => Text(
    name,
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}

/// A row's detail line, up to two lines: [lead], such as the category,
/// flows and wraps like any text, and [tail], such as the account
/// ("Equity Bank ···8765"), always shows whole after a " · ". When both
/// do not fit, [lead] shortens with "…".
class DetailLine extends StatelessWidget {
  const DetailLine(this.lead, this.tail, {this.style, super.key});

  final String lead;
  final String tail;
  final TextStyle? style;

  static const _maxLines = 2;

  /// [text] with no place to break a line: spaces stay together and a
  /// hyphen keeps its word ("M-Pesa").
  static String _unbroken(String text) =>
      text.replaceAll(' ', ' ').replaceAll('-', '-⁠');

  @override
  Widget build(BuildContext context) {
    final shown = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // The dot stays with the end of [lead]; the line may break after it.
    final end = ' · ${_unbroken(tail)}';
    return Semantics(
      label: '$lead · $tail',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          bool fits(String text) {
            final painter = TextPainter(
              text: TextSpan(text: text, style: shown),
              textDirection: direction,
              textScaler: scaler,
              maxLines: _maxLines,
            )..layout(maxWidth: constraints.maxWidth);
            final fit = !painter.didExceedMaxLines;
            painter.dispose();
            return fit;
          }

          var text = '$lead$end';
          if (!fits(text)) {
            final chars = lead.characters.toList();
            String cut(int n) => '${chars.take(n).join().trimRight()}…$end';
            var low = 0;
            var high = chars.length;
            while (low < high) {
              final mid = (low + high + 1) ~/ 2;
              if (fits(cut(mid))) {
                low = mid;
              } else {
                high = mid - 1;
              }
            }
            text = cut(low);
          }
          return Text(
            text,
            maxLines: _maxLines,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        },
      ),
    );
  }
}

/// The Pesa Clarity mark: a white P on a red rounded square.
class AppMark extends StatelessWidget {
  const AppMark({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Pesa Clarity',
      image: true,
      child: ExcludeSemantics(
        child: Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'P',
            style: Theme.of(context).textTheme.headlineSmall!.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w700,
              fontVariations: const [FontVariation.weight(700)],
            ),
          ),
        ),
      ),
    );
  }
}
