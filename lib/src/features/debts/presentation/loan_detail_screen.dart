import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/debts/debt.dart';
import '../../../domain/debts/next_due.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/format/date_labels.dart' show relativeDays, weekdayName;
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/domain/institution.dart';
import '../application/debts_overview_provider.dart';
import 'debt_sheet.dart';
import 'debts_screen.dart' show debtRateLabel;
import 'due_line.dart';

/// Opens the details of the loan [debtId].
Future<void> showLoanDetail(BuildContext context, int debtId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LoanDetailScreen(debtId: debtId)),
    );

/// One loan laid out plainly: what is left, the next instalment and when it
/// is due, the last payment, and where the due date came from.
///
/// Message text is never kept (only a hash of it), so the screen names the
/// message's sender and day rather than quoting it.
class LoanDetailScreen extends ConsumerWidget {
  const LoanDetailScreen({required this.debtId, super.key});

  final int debtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(debtsOverviewProvider);
    final overview = state.value;
    final debt = overview?.debts.where((d) => d.id == debtId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(debt?.lender ?? 'Loan'),
        actions: [
          if (overview != null && debt != null) ...[
            PillButton(
              label: 'Edit',
              tooltip: 'Edit this loan',
              onPressed: () =>
                  showDebtSheet(context, today: overview.today, debt: debt),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: overview == null
          ? state.hasError
                ? ErrorView(
                    'This loan could not load.',
                    onRetry: () => ref.invalidate(debtsOverviewProvider),
                  )
                : const LoadingView()
          : debt == null
          ? const _Gone()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Layout.gutter,
                8,
                Layout.gutter,
                Layout.screenBottom,
              ),
              children: [
                _BalanceCard(
                  debt: debt,
                  paidFraction: overview.paidFraction(debt),
                  cleared: overview.plan.debt(debt.id).paidOffIn,
                ),
                const SizedBox(height: Layout.cardGap),
                _ScheduleCard(debt: debt, today: overview.today),
              ],
            ),
    );
  }
}

/// The loan is paid off or was deleted.
class _Gone extends StatelessWidget {
  const _Gone();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Layout.gutter),
    child: Text(
      'Nothing is owed on this loan now.',
      style: Theme.of(context).textTheme.bodyLarge,
    ),
  );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.debt,
    required this.paidFraction,
    required this.cleared,
  });

  final Debt debt;
  final double paidFraction;
  final YearMonth? cleared;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final paid = (paidFraction * 100).floor();
    final details = [
      '$paid% paid',
      if (debt.chargesInterest)
        '${debtRateLabel(debt.annualRateBasisPoints)} p.a.',
      if (cleared case final month?) 'cleared ${monthLabel(month)}',
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Outstanding balance',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            FigureText(
              shownMoney(context, debt.balanceMinor, withCurrency: true),
              style: AppTypography.headlineFigure(theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: paidFraction,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
              color: colors.link,
              backgroundColor: colors.border,
              semanticsLabel: '$paid% paid',
            ),
            const SizedBox(height: 8),
            Text(
              details,
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleCard extends ConsumerWidget {
  const _ScheduleCard({required this.debt, required this.today});

  final Debt debt;
  final CalendarDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = debt.nextDue;
    final last = debt.lastPayment;
    final rows = <Widget>[
      if (debt.minimumPaymentMinor > 0)
        _Fact(
          label: 'Next payment',
          value: shownMoney(
            context,
            debt.minimumPaymentMinor,
            withCurrency: true,
          ),
          amount: true,
        ),
      if (due != null) _dueRow(context, due),
      if (last != null)
        _Fact(
          label: 'Last payment',
          value: shownMoney(context, last.amountMinor, withCurrency: true),
          amount: true,
          note:
              '${_weekday(last.date)}, '
              '${dayLabel(last.date, thisYear: today.year)}',
        ),
      if (due != null) _SourceLine(due.source, today: today),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _dueRow(BuildContext context, NextDue due) {
    final state = due.statusOn(today).state;
    final (_, color) = dueLook(context, state);
    return _Fact(
      label: 'Due',
      value: '${_weekday(due.date)}, ${dateLabel(due.date)}',
      note: state == DueState.paid
          ? 'paid since'
          : relativeDays(due.date, today: today),
      noteColor: color,
    );
  }
}

String _weekday(CalendarDate date) => weekdayName(date).substring(0, 3);

/// A line of the loan's schedule: [label] at the start, [value] at the end
/// and [note] under the value. As in [LabelValueRow], the value stays beside
/// the label while both fit with no word of the label broken, and otherwise
/// takes its own line under it, so an amount is never split.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.amount = false,
    this.note,
    this.noteColor,
  });

  final String label;

  /// Already formatted, and masked while amounts are hidden.
  final String value;

  /// Whether [value] is an amount, drawn whole as [FigureText] draws one.
  final bool amount;
  final String? note;

  /// The note's colour when it means something, such as amber when the day
  /// is close; muted otherwise.
  final Color? noteColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final labelStyle = theme.textTheme.bodyMedium!.copyWith(
      color: colors.textMuted,
    );
    final valueStyle = theme.textTheme.bodyLarge!.copyWith(
      color: theme.colorScheme.onSurface,
      fontWeight: FontWeight.w600,
    );
    final noteStyle = theme.textTheme.bodySmall!.copyWith(
      color: noteColor ?? colors.textMuted,
      fontWeight: noteColor == null ? null : FontWeight.w600,
    );
    final note = this.note;
    final end = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (amount)
          FigureText(value, style: valueStyle)
        else
          Text(value, style: valueStyle, textAlign: TextAlign.end),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(note, style: noteStyle, textAlign: TextAlign.end),
        ],
      ],
    );
    final needs =
        _widestWord(context, label, labelStyle) +
        Layout.cardGap +
        math.max(
          amount
              ? FigureText.numberWidth(context, value, valueStyle)
              : textLineWidth(context, value, valueStyle),
          note == null ? 0.0 : textLineWidth(context, note, noteStyle),
        );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Layout.cardPadding,
          vertical: 14,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => needs <= constraints.maxWidth
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(label, style: labelStyle)),
                    const SizedBox(width: Layout.cardGap),
                    end,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(label, style: labelStyle),
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: end,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The widest word of [text] in [style] at the phone's text size: the
/// narrowest it can wrap to.
double _widestWord(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.minIntrinsicWidth;
  painter.dispose();
  return width;
}

/// Where the due date came from: `From your KCB messages · 20 Nov`, or the
/// person's own edit.
class _SourceLine extends ConsumerWidget {
  const _SourceLine(this.source, {required this.today});

  final DueSource? source;
  final CalendarDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final style = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    final from = source;
    final InlineSpan text;
    final IconData icon;
    if (from == null) {
      icon = Icons.edit_outlined;
      text = const TextSpan(text: 'Due date set by you');
    } else {
      icon = Icons.chat_bubble_outline;
      final institution = ref
          .watch(institutionCatalogueProvider)
          .where((i) => i.id == from.institutionId)
          .firstOrNull;
      final name = institution?.name ?? from.account;
      final day = dayLabel(
        CalendarDate.local(from.readAt),
        thisYear: today.year,
      );
      text = TextSpan(
        children: [
          if (name == null)
            const TextSpan(text: 'From your messages')
          else ...[
            const TextSpan(text: 'From your '),
            TextSpan(
              text: name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const TextSpan(text: ' messages'),
          ],
          TextSpan(text: ' · $day'),
        ],
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Layout.cardPadding,
        vertical: 12,
      ),
      child: IconLine(
        icon: icon,
        text: text,
        style: style,
        iconSize: 16,
        gap: 8,
      ),
    );
  }
}
