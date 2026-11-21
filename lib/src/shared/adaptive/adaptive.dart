import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/layout.dart';
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
            // A red fill takes white text, in light and dark.
            ? (style ?? const ButtonStyle()).merge(
                FilledButton.styleFrom(
                  backgroundColor: PesaColors.of(context).danger,
                  foregroundColor: scheme.onPrimary,
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
      : LayoutBuilder(
          builder: (context, constraints) {
            final scaler = _sideBySideScaler(context, constraints.maxWidth);
            final button = SegmentedButton<T>(
              // Side by side while every word of every label fits its half,
              // at the phone's text size or a little under it; otherwise
              // one above the other, so no word breaks.
              direction: scaler != null ? Axis.horizontal : Axis.vertical,
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
            final base = MediaQuery.textScalerOf(context);
            if (scaler == null || scaler == base) return button;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: scaler),
              child: button,
            );
          },
        );

  /// Room a segment takes beyond its label: its padding, its border and,
  /// when chosen, the tick.
  static const _segmentChrome = 40.0;
  static const _tick = 26.0;

  /// The smallest share of the phone's text size the labels may take to
  /// stay side by side: at twice the size, no smaller than 1.5 times. As the
  /// tab bar does, every label takes the one size.
  static const _minShare = 0.75;

  /// The text size at which the segments fit side by side in [width]: the
  /// phone's when they fit at it, otherwise the largest at which they do,
  /// down to [_minShare] of it (never under the usual size). Null when they
  /// do not fit even then, and so go one above the other.
  TextScaler? _sideBySideScaler(BuildContext context, double width) {
    final base = MediaQuery.textScalerOf(context);
    if (!width.isFinite) return base;
    final style = Theme.of(context).textTheme.labelLarge!;
    final each = width / segments.length;
    final room = each - _segmentChrome - (showSelectedIcon ? _tick : 0);
    double widestWord(TextScaler scaler) {
      var widest = 0.0;
      for (final (_, label) in segments) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: style),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout();
        widest = math.max(widest, painter.minIntrinsicWidth);
        painter.dispose();
      }
      return widest;
    }

    final size = style.fontSize ?? 14;
    final full = base.scale(size) / size;
    final floor = math.max(1.0, full * _minShare);
    var factor = full;
    // Width is not quite in proportion to size, so narrow it in a few steps.
    for (var i = 0; i < 4; i++) {
      final scaler = factor == full ? base : TextScaler.linear(factor);
      final w = widestWord(scaler);
      if (w <= room) return scaler;
      if (factor <= floor || room <= 0) return null;
      factor = math.max(floor, factor * room / w * 0.99);
    }
    final last = TextScaler.linear(factor);
    return widestWord(last) <= room ? last : null;
  }
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
            padding: const EdgeInsetsDirectional.fromSTEB(
              4,
              Layout.sectionTop,
              16,
              Layout.sectionBottom,
            ),
            child: Semantics(header: true, child: Text(header!, style: note)),
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
