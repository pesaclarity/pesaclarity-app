import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/pesa_colors.dart';

/// Whether to draw iPhone-style controls: true on iOS, where the theme's
/// platform is iOS, so widget tests can switch it too.
bool isCupertino(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS;

/// A dialog button: a [CupertinoDialogAction] on iPhone, a [TextButton]
/// elsewhere, or a [FilledButton] when [filled]. [destructive] actions show
/// in red on iPhone.
class DialogAction extends StatelessWidget {
  const DialogAction({
    required this.onPressed,
    required this.child,
    this.destructive = false,
    this.isDefault = false,
    this.filled = false,
    this.style,
    super.key,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final bool destructive;
  final bool isDefault;

  /// Whether Android shows it as the main, filled button.
  final bool filled;

  /// The Android button's style.
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) => isCupertino(context)
      ? CupertinoDialogAction(
          onPressed: onPressed,
          isDestructiveAction: destructive,
          isDefaultAction: isDefault,
          child: child,
        )
      : filled
      ? FilledButton(onPressed: onPressed, style: style, child: child)
      : TextButton(onPressed: onPressed, style: style, child: child);
}

/// Picks a day: the wheel in a bottom panel on iPhone, the calendar dialog
/// elsewhere. Returns null when dismissed.
Future<DateTime?> pickDate(
  BuildContext context, {
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  if (!isCupertino(context)) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }
  var picked = initialDate;
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (context) => _CupertinoPanel(
      onDone: () => Navigator.of(context).pop(picked),
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.date,
        initialDateTime: initialDate,
        minimumDate: firstDate,
        maximumDate: lastDate,
        onDateTimeChanged: (value) => picked = value,
      ),
    ),
  );
}

/// Picks a time of day, as [pickDate] does.
Future<TimeOfDay?> pickTime(
  BuildContext context, {
  required TimeOfDay initialTime,
  String? helpText,
}) {
  if (!isCupertino(context)) {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: helpText,
    );
  }
  var picked = initialTime;
  final now = DateTime.now();
  return showCupertinoModalPopup<TimeOfDay>(
    context: context,
    builder: (context) => _CupertinoPanel(
      onDone: () => Navigator.of(context).pop(picked),
      child: CupertinoDatePicker(
        mode: CupertinoDatePickerMode.time,
        initialDateTime: DateTime(
          now.year,
          now.month,
          now.day,
          initialTime.hour,
          initialTime.minute,
        ),
        onDateTimeChanged: (value) => picked = TimeOfDay.fromDateTime(value),
      ),
    ),
  );
}

/// The panel that holds a wheel picker, with Done at the top right.
class _CupertinoPanel extends StatelessWidget {
  const _CupertinoPanel({required this.onDone, required this.child});

  final VoidCallback onDone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 300,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                onPressed: onDone,
                child: Text(
                  'Done',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

/// A choice of two to four: the sliding control on iPhone, a
/// [SegmentedButton] elsewhere.
class AdaptiveSegmented<T extends Object> extends StatelessWidget {
  const AdaptiveSegmented({
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.showSelectedIcon = true,
    super.key,
  });

  final List<(T, String)> segments;

  /// Whether Android shows a tick on the chosen segment.
  final bool showSelectedIcon;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    if (isCupertino(context)) {
      return SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<T>(
          groupValue: selected,
          onValueChanged: (value) {
            if (value != null) onChanged(value);
          },
          children: {
            for (final (value, label) in segments)
              value: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(label),
              ),
          },
        ),
      );
    }
    return SegmentedButton<T>(
      showSelectedIcon: showSelectedIcon,
      segments: [
        for (final (value, label) in segments)
          ButtonSegment(value: value, label: Text(label)),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onChanged(values.single),
    );
  }
}

/// Rows in a group. On iPhone, an inset grouped list as in Settings, with
/// an optional uppercase [header] and [footer]. Elsewhere, a card with
/// dividers, as in the Android design, with the header above it.
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
    final cupertino = isCupertino(context);
    final note = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: EdgeInsets.fromLTRB(cupertino ? 16 : 4, 16, 16, 6),
            child: Text(
              cupertino ? header!.toUpperCase() : header!,
              style: note.copyWith(letterSpacing: cupertino ? 0.2 : null),
            ),
          ),
        Card(
          child: Column(
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0)
                  Divider(
                    height: cupertino ? 0.5 : 1,
                    indent: cupertino ? 60 : 0,
                  ),
                child,
              ],
            ],
          ),
        ),
        if (footer != null)
          Padding(
            padding: EdgeInsets.fromLTRB(cupertino ? 16 : 4, 6, 16, 0),
            child: Text(footer!, style: note),
          ),
      ],
    );
  }
}

/// A row's leading icon: white on a coloured rounded square on iPhone, as
/// in Settings; a plain icon elsewhere.
class RowIcon extends StatelessWidget {
  const RowIcon(
    this.icon, {
    required this.cupertinoIcon,
    required this.color,
    super.key,
  });

  final IconData icon;

  /// The icon on iPhone.
  final IconData cupertinoIcon;

  /// The square's colour on iPhone.
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!isCupertino(context)) return Icon(icon);
    return Container(
      width: 29,
      height: 29,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(cupertinoIcon, size: 18, color: CupertinoColors.white),
    );
  }
}
