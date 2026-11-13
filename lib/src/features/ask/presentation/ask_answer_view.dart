import 'package:flutter/material.dart';

import '../../../domain/ask/answer.dart';
import '../../../domain/ask/matcher.dart';
import '../../../domain/ask/periods.dart';
import '../../../domain/ask/reply_writer.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import 'ask_strings.dart';

/// [answer]'s sentence with its facts filled in, amounts masked while
/// hidden.
String answerText(BuildContext context, AskAnswer answer) => fillTemplate(
  answer.template,
  answer.facts,
  money: (minor) => shownMoney(context, minor, withCurrency: false),
);

/// The person's question: a soft pink bubble on the right.
class QuestionBubble extends StatelessWidget {
  const QuestionBubble(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        margin: const EdgeInsets.only(left: 48, bottom: Layout.cardGap),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Layout.panelRadius),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyLarge!.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// A reply card: what it is, the figure, the sentence, a chart, the top
/// rows, and when its numbers are from.
class AnswerCard extends StatelessWidget {
  const AnswerCard({
    required this.answer,
    required this.today,
    required this.charts,
    this.onUpdate,
    this.onSeeAll,
    this.onChoose,
    super.key,
  });

  final AskAnswer answer;
  final CalendarDate today;
  final bool charts;
  final VoidCallback? onUpdate;
  final VoidCallback? onSeeAll;

  /// For a clarify card: the person's pick (null for all) and the period.
  final void Function(AskEntity? choice, AskPeriod period)? onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    final text = answerText(context, answer);
    if (answer.kind == ReplyKind.clarify) {
      return _ClarifyCard(
        answer: answer,
        question: text,
        today: today,
        onChoose: onChoose,
      );
    }
    final figure =
        answer.figureText ??
        (answer.figureMinor == null
            ? null
            : shownMoney(context, answer.figureMinor!, withCurrency: true));
    final old = answer.asOfDate != today;
    final chart = answer.chart;
    return Card(
      key: const Key('ask-answer'),
      margin: const EdgeInsets.only(bottom: Layout.cardGap),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (answer.headline != null) ...[
              Text(answer.headline!, style: muted),
              const SizedBox(height: 6),
            ],
            if (figure != null) ...[
              Text(
                figure,
                style: answer.figureText != null
                    ? AppTypography.tileFigure(theme.colorScheme.onSurface)
                    : AppTypography.headlineFigure(theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
            ],
            if (text.isNotEmpty)
              Text(
                text,
                style: figure == null
                    ? theme.textTheme.bodyLarge
                    : theme.textTheme.bodyMedium,
              ),
            if (answer.kind == ReplyKind.cant) ...[
              const SizedBox(height: 12),
              Text(AskStrings.theseMightHelp, style: muted),
            ],
            if (charts && chart != null) ...[
              const SizedBox(height: 16),
              if (chart.isShare) ShareBar(chart) else MonthBars(chart.bars),
            ],
            if (answer.rows.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(),
              for (final row in answer.rows) _Row(row),
            ],
            if (old && answer.canUpdate) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '${AskStrings.numbersAsOf(dayLabel(answer.asOfDate, thisYear: today.year))} · ',
                    style: muted,
                  ),
                  InkWell(
                    key: const Key('ask-update'),
                    onTap: onUpdate,
                    child: Text(
                      AskStrings.update,
                      style: muted.copyWith(
                        color: colors.link,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (onSeeAll != null && _seeAll != null) ...[
              const SizedBox(height: 12),
              InkWell(
                key: const Key('ask-see-all'),
                onTap: onSeeAll,
                child: Text(
                  '$_seeAll ›',
                  style: theme.textTheme.labelLarge!.copyWith(
                    color: colors.link,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? get _seeAll {
    if (answer.link == null) return null;
    if (answer.link == AskLink.businessInsights) {
      return AskStrings.openBusinessInsights;
    }
    if (answer.chart != null) {
      return AskStrings.seePayments;
    }
    if (answer.totalRows > answer.rows.length) {
      return AskStrings.seeAll(answer.totalRows);
    }
    return null;
  }
}

class _Row extends StatelessWidget {
  const _Row(this.row);

  final AskRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title, style: theme.textTheme.bodyLarge),
                if (row.detail != null)
                  Text(
                    row.detail!,
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
          if (row.amountMinor != null)
            Text(
              shownMoney(context, row.amountMinor!, withCurrency: false),
              style: theme.textTheme.titleMedium,
            ),
        ],
      ),
    );
  }
}

/// Month by month bars, the highest months in full colour.
class MonthBars extends StatelessWidget {
  const MonthBars(this.bars, {super.key});

  final List<AskBar> bars;

  static const _height = 96.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final largest = bars.fold(0, (m, b) => b.valueMinor > m ? b.valueMinor : m);
    return Semantics(
      label: [
        for (final b in bars)
          '${b.label} ${shownMoney(context, b.valueMinor, withCurrency: false)}',
      ].join(', '),
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final b in bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  children: [
                    Container(
                      height:
                          6 +
                          (_height - 6) *
                              (largest <= 0 ? 0 : b.valueMinor / largest),
                      decoration: BoxDecoration(
                        color: b.highlight
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.22,
                              ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      b.label,
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A part of a whole as one split bar with both shares below.
class ShareBar extends StatelessWidget {
  const ShareBar(this.chart, {super.key});

  final AskChart chart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final percent = chart.partPercent.clamp(0, 100);
    final label = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (percent > 0)
                  Expanded(
                    flex: percent,
                    child: ColoredBox(color: theme.colorScheme.primary),
                  ),
                if (percent < 100)
                  Expanded(
                    flex: 100 - percent,
                    child: ColoredBox(color: colors.brandSoft),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: Text('${chart.partLabel} $percent%', style: label)),
            Text('${chart.restLabel} ${100 - percent}%', style: label),
          ],
        ),
      ],
    );
  }
}

/// "Which John do you mean?": the choices, Both, and when.
class _ClarifyCard extends StatefulWidget {
  const _ClarifyCard({
    required this.answer,
    required this.question,
    required this.today,
    required this.onChoose,
  });

  final AskAnswer answer;
  final String question;
  final CalendarDate today;
  final void Function(AskEntity? choice, AskPeriod period)? onChoose;

  @override
  State<_ClarifyCard> createState() => _ClarifyCardState();
}

class _ClarifyCardState extends State<_ClarifyCard> {
  late AskPeriod _period =
      widget.answer.context.period ?? AskPeriod.thisMonth(widget.today);

  List<(AskPeriod, String)> get _periods {
    final today = widget.today;
    final options = [
      (AskPeriod.thisMonth(today), AskStrings.periodThisMonth),
      (
        AskPeriod.month(today.yearMonth.previous, today),
        AskStrings.periodLastMonth,
      ),
      (AskPeriod.thisWeek(today), AskStrings.periodThisWeek),
      (AskPeriod.lastMonths(3, today), AskStrings.periodLast3Months),
      (AskPeriod.thisYear(today), AskStrings.periodThisYear),
    ];
    if (!options.any((o) => o.$1 == _period)) {
      options.insert(0, (_period, _period.label(today)));
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final choices = widget.answer.choices;
    final enabled = widget.onChoose != null;
    Widget option(String title, String? detail, AskEntity? entity, Key key) =>
        InkWell(
          key: key,
          onTap: enabled ? () => widget.onChoose!(entity, _period) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      if (detail != null)
                        Text(
                          detail,
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return Card(
      key: const Key('ask-clarify'),
      margin: const EdgeInsets.only(bottom: Layout.cardGap),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.question, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(Layout.tagRadius),
              ),
              child: Column(
                children: [
                  for (final (i, c) in choices.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    option(c.name, c.detail, c, Key('ask-choice-$i')),
                  ],
                  if (choices.length > 1) ...[
                    const Divider(height: 1),
                    option(
                      choices.length == 2 ? AskStrings.both : AskStrings.all,
                      AskStrings.bothDetail,
                      null,
                      const Key('ask-choice-all'),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.answer.askPeriod) ...[
              const SizedBox(height: 12),
              Text(
                AskStrings.andForWhen,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              ChoiceMenu<AskPeriod>(
                name: AskStrings.andForWhen,
                expand: true,
                options: _periods,
                value: _period,
                onChanged: (p) => setState(() => _period = p),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Follow-ups to tap.
class SuggestionChips extends StatelessWidget {
  const SuggestionChips(this.suggestions, {required this.onTap, super.key});

  final List<String> suggestions;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Layout.cardGap),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in suggestions)
          ActionChip(
            avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
            label: Text(s),
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
            side: BorderSide.none,
            onPressed: () => onTap(s),
          ),
      ],
    ),
  );
}
