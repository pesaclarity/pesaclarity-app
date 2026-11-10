import 'package:flutter/material.dart';

import '../../theme/pesa_colors.dart';
import '../widgets/choice_menu.dart';

// iPhone uses the same design as Android (decision 0011): these helpers
// keep one place for dialogs, pickers, choices and grouped rows.

/// A dialog button: a [TextButton], or a [FilledButton] when [filled].
/// [destructive] actions show in the error colour.
class DialogAction extends StatelessWidget {
  const DialogAction({
    required this.onPressed,
    required this.child,
    this.destructive = false,
    this.filled = false,
    this.style,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool destructive;

  /// Whether it is the main, filled button.
  final bool filled;
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton(onPressed: onPressed, style: style, child: child);
    }
    final error = Theme.of(context).colorScheme.error;
    return TextButton(
      onPressed: onPressed,
      style: destructive
          ? (style ?? const ButtonStyle()).merge(
              TextButton.styleFrom(foregroundColor: error),
            )
          : style,
      child: child,
    );
  }
}

/// Picks a day in the calendar dialog. Returns null when dismissed.
Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) => showDatePicker(
  context: context,
  initialDate: initialDate,
  firstDate: firstDate,
  lastDate: lastDate,
);

/// Picks a time of day in the clock dialog. Returns null when dismissed.
Future<TimeOfDay?> pickTime(
  BuildContext context, {
  required TimeOfDay initialTime,
  String? helpText,
}) => showTimePicker(
  context: context,
  initialTime: initialTime,
  helpText: helpText,
);

/// A choice of two as a [SegmentedButton]; more than two as a drop-down
/// ([ChoiceMenu]).
class AdaptiveSegmented<T extends Object> extends StatelessWidget {
  const AdaptiveSegmented({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.showSelectedIcon = true,
    this.name,
    super.key,
  });

  final List<(T, String)> segments;

  /// What is being chosen, such as `Period`, for screen readers when it
  /// shows as a drop-down.
  final String? name;

  /// Whether the chosen segment shows a tick.
  final bool showSelectedIcon;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => segments.length > 2
      ? Align(
          alignment: AlignmentDirectional.centerStart,
          child: ChoiceMenu<T>(
            name: name,
            options: segments,
            value: selected,
            onChanged: onChanged,
          ),
        )
      : SegmentedButton<T>(
          showSelectedIcon: showSelectedIcon,
          segments: [
            for (final (value, label) in segments)
              ButtonSegment(value: value, label: Text(label)),
          ],
          selected: {selected},
          onSelectionChanged: (values) => onChanged(values.single),
        );
}

/// Rows in a card with dividers, with an optional [header] above it and
/// [footer] below.
class GroupedSection extends StatelessWidget {
  const GroupedSection({
    required this.children,
    this.header,
    this.footer,
    super.key,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final note = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 16, 6),
            child: Text(header!, style: note),
          ),
        Card(
          child: Column(
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0) const Divider(height: 1),
                child,
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 16, 0),
            child: Text(footer!, style: note),
          ),
      ],
    );
  }
}

/// A row's leading icon.
class RowIcon extends StatelessWidget {
  const RowIcon(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Icon(icon);
}
