import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/debts/next_due.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../theme/pesa_colors.dart';

/// What the due line says for [due] on [today], such as
/// `Next KES 2,500 due 5 Dec`, or null once it was paid. [amount] is the
/// instalment as shown, such as `KES 2,500`; null when not known.
String? dueLineText(
  NextDue due, {
  required CalendarDate today,
  String? amount,
}) {
  final status = due.statusOn(today);
  final day = dayLabel(due.date, thisYear: today.year);
  final next = amount == null ? 'Next payment' : 'Next $amount';
  return switch (status.state) {
    DueState.later => '$next due $day',
    DueState.soon when status.days == 1 => '$next due tomorrow, $day',
    DueState.soon => '$next due in ${status.days} days, $day',
    DueState.today => '$next due today',
    DueState.late =>
      '${amount ?? 'A payment'} was due $day · '
          '${status.daysLate == 1 ? '1 day' : '${status.daysLate} days'} late',
    DueState.paid => null,
  };
}

/// When a loan's next instalment is due, under its row: plain while there
/// is time, amber within three days and red once it is late with no
/// repayment since. Nothing once it was paid.
class DueLine extends StatelessWidget {
  const DueLine({
    required this.due,
    required this.today,
    required this.amountMinor,
    super.key,
  });

  final NextDue due;
  final CalendarDate today;

  /// The instalment; 0 when not known.
  final int amountMinor;

  @override
  Widget build(BuildContext context) {
    final text = dueLineText(
      due,
      today: today,
      amount: amountMinor > 0
          ? shownMoney(context, amountMinor, withCurrency: true)
          : null,
    );
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final (icon, color) = dueLook(context, due.statusOn(today).state);
    return IconLine(
      icon: icon,
      text: TextSpan(text: text),
      style: theme.textTheme.bodySmall!.copyWith(
        color: color ?? theme.colorScheme.onSurface,
        fontWeight: color == null ? null : FontWeight.w600,
      ),
    );
  }
}

/// [text] after a small [icon] in the text's colour. The icon grows with
/// the text and sits on its first line; a longer text wraps under itself.
class IconLine extends StatelessWidget {
  const IconLine({
    required this.icon,
    required this.text,
    required this.style,
    this.iconColor,
    this.iconSize = 14,
    this.gap = 6,
    super.key,
  });

  final IconData icon;
  final InlineSpan text;
  final TextStyle style;

  /// The icon's colour; the text's by default.
  final Color? iconColor;

  /// The icon's size at the usual text size.
  final double iconSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final size = scaler.scale(iconSize);
    final firstLine = TextPainter(
      text: TextSpan(text: ' ', style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    final lineHeight = firstLine.preferredLineHeight;
    firstLine.dispose();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: SizedBox(
            height: math.max(lineHeight, size),
            child: Center(
              child: Icon(icon, size: size, color: iconColor ?? style.color),
            ),
          ),
        ),
        SizedBox(width: gap),
        Expanded(child: Text.rich(text, style: style)),
      ],
    );
  }
}

/// The icon and colour for [state]: a calendar while there is time, an
/// amber clock when close, a red alert when late. A null colour is the
/// text's own.
(IconData, Color?) dueLook(BuildContext context, DueState state) =>
    switch (state) {
      DueState.later || DueState.paid => (Icons.event_outlined, null),
      DueState.soon ||
      DueState.today => (Icons.schedule, PesaColors.of(context).warning),
      DueState.late => (
        Icons.error_outline,
        Theme.of(context).colorScheme.error,
      ),
    };
