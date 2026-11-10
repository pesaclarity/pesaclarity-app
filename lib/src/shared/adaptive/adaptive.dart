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
    final scheme = Theme.of(context).colorScheme;
    final error = scheme.error;
    if (filled) {
      return FilledButton(
        onPressed: onPressed,
        style: destructive
            ? (style ?? const ButtonStyle()).merge(
                FilledButton.styleFrom(
                  backgroundColor: error,
                  foregroundColor: scheme.onError,
                ),
              )
            : style,
        child: child,
      );
    }
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

/// Picks a run of days in the calendar. Returns null when dismissed.
Future<DateTimeRange?> pickDateRange(
  BuildContext context, {
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
}) => showDateRangePicker(
  context: context,
  firstDate: firstDate,
  lastDate: lastDate,
  initialDateRange: initialDateRange,
);

/// Asks before something is deleted: [title] as a question, such as
/// "Delete Rent?", one sentence of [body], then Keep and [action]. True
/// when the person chose [action].
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String body,
  String action = 'Delete',
}) async {
  final yes = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text(title),
      content: Text(body),
      actions: [
        DialogAction(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep'),
        ),
        DialogAction(
          destructive: true,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return yes ?? false;
}

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
    this.segmentKey,
    super.key,
  });

  final List<(T, String)> segments;

  /// A key for each choice, for tests and UI flows.
  final Key Function(T value)? segmentKey;

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
            itemKey: segmentKey,
          ),
        )
      : SegmentedButton<T>(
          showSelectedIcon: showSelectedIcon,
          segments: [
            for (final (value, label) in segments)
              ButtonSegment(
                value: value,
                label: Text(label, key: segmentKey?.call(value)),
              ),
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
