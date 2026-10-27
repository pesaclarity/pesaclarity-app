import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/insights/spending_charts.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../application/insights_providers.dart';

String _amount(int minor) => formatMoney(Money(minor), withCurrency: false);

/// Colours for chart series, from the theme, told apart by lightness as well
/// as hue. The last is for "Other".
List<Color> chartSeries(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final colors = PesaColors.of(context);
  return [
    scheme.primary,
    colors.warning,
    colors.success,
    scheme.primary.withValues(alpha: .45),
    colors.textMuted,
    colors.border,
  ];
}

String _periodName(ChartPeriod period) => switch (period) {
  ChartPeriod.week => 'week',
  ChartPeriod.month => 'month',
  ChartPeriod.year => 'year',
};

/// Insights: the period switch, spending by category as a ring, and spending
/// so far against the period before as two lines.
class SpendingChartsSection extends ConsumerWidget {
  const SpendingChartsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(chartPeriodProvider);
    final chart = ref.watch(spendingChartProvider).value;
    final names = ref.watch(categoryNamesProvider).value ?? const {};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<ChartPeriod>(
          key: const Key('chart-period'),
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ChartPeriod.week, label: Text('Week')),
            ButtonSegment(value: ChartPeriod.month, label: Text('Month')),
            ButtonSegment(value: ChartPeriod.year, label: Text('Year')),
          ],
          selected: {period},
          onSelectionChanged: (s) =>
              ref.read(chartPeriodProvider.notifier).select(s.single),
        ),
        const SizedBox(height: 12),
        if (chart == null)
          const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          _BreakdownCard(chart: chart, names: names, period: period),
          const SizedBox(height: 12),
          _SoFarCard(chart: chart, period: period),
        ],
      ],
    );
  }
}

String sliceLabel(SliceKey key, Map<int, String> names) => switch (key) {
  CategorySlice(:final categoryId) => names[categoryId] ?? 'Category',
  FeesSlice() => 'Fees',
  UncategorisedSlice() => 'Uncategorised',
  OtherSlice() => 'Other',
};

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.chart,
    required this.names,
    required this.period,
  });

  final SpendingChart chart;
  final Map<int, String> names;
  final ChartPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final series = chartSeries(context);
    Color colorOf(int i, SliceKey key) =>
        key is OtherSlice ? series.last : series[i % (series.length - 1)];

    if (chart.slices.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Spending this ${_periodName(period)} shows here as it comes in.',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
        ),
      );
    }

    final description = [
      for (final s in chart.slices)
        '${sliceLabel(s.key, names)} ${_amount(s.amountMinor)}',
    ].join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Semantics(
              label: 'Spending by category: $description',
              excludeSemantics: true,
              child: SizedBox.square(
                dimension: 128,
                child: CustomPaint(
                  painter: _RingPainter(
                    fractions: [
                      for (final s in chart.slices)
                        s.amountMinor / chart.totalMinor,
                    ],
                    colors: [
                      for (final (i, s) in chart.slices.indexed)
                        colorOf(i, s.key),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Spent',
                          style: theme.textTheme.labelSmall!.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        Text(
                          _amount(chart.totalMinor),
                          style: AppTypography.amount(
                            size: 18,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                children: [
                  for (final (i, s) in chart.slices.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: colorOf(i, s.key),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              sliceLabel(s.key, names),
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          Text(
                            _amount(s.amountMinor),
                            style: theme.textTheme.bodySmall!.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.fractions, required this.colors});

  final List<double> fractions;
  final List<Color> colors;

  static const _stroke = 16.0;
  static const _gap = 0.03;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.shortestSide / 2 - _stroke / 2,
    );
    final gap = fractions.length > 1 ? _gap : 0.0;
    var start = -math.pi / 2;
    for (final (i, fraction) in fractions.indexed) {
      final sweep = fraction * 2 * math.pi;
      canvas.drawArc(
        rect,
        start + gap / 2,
        math.max(sweep - gap, 0.001),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..color = colors[i],
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fractions != fractions || old.colors != colors;
}

class _SoFarCard extends StatelessWidget {
  const _SoFarCard({required this.chart, required this.period});

  final SpendingChart chart;
  final ChartPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final name = _periodName(period);
    final change = chart.changeToDateMinor;
    final (changeText, changeColor) = switch (change) {
      null => (null, null),
      0 => ('Same as last $name', colors.textMuted),
      < 0 => ('${_amount(-change)} under last $name', colors.successText),
      _ => ('${_amount(change)} over last $name', colors.warning),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'This $name so far',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (changeText != null)
                  Text(
                    changeText,
                    key: const Key('chart-change'),
                    style: theme.textTheme.labelMedium!.copyWith(
                      color: changeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              label:
                  'Spending so far this $name: '
                  '${_amount(chart.cumulative.lastOrNull ?? 0)}. '
                  'Last $name in all: '
                  '${_amount(chart.previousCumulative.lastOrNull ?? 0)}.',
              excludeSemantics: true,
              child: SizedBox(
                height: 120,
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _LinesPainter(
                    current: chart.cumulative,
                    previous: chart.previousCumulative,
                    days: math.max(
                      chart.window.days,
                      chart.previousCumulative.length,
                    ),
                    currentColor: theme.colorScheme.primary,
                    previousColor: colors.textMuted,
                    gridColor: colors.border,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Key(color: theme.colorScheme.primary, label: 'This $name'),
                const SizedBox(width: 16),
                _Key(
                  color: colors.textMuted,
                  label: 'Last $name',
                  dashed: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label, this.dashed = false});

  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 14,
        height: dashed ? 2 : 3,
        color: dashed ? color.withValues(alpha: .6) : color,
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _LinesPainter extends CustomPainter {
  _LinesPainter({
    required this.current,
    required this.previous,
    required this.days,
    required this.currentColor,
    required this.previousColor,
    required this.gridColor,
  });

  final List<int> current;
  final List<int> previous;
  final int days;
  final Color currentColor;
  final Color previousColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final y in [0.0, size.height / 2, size.height]) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final top = [...current, ...previous].fold(0, math.max);
    if (top <= 0 || days < 2) return;

    Offset point(int day, int total) => Offset(
      size.width * day / (days - 1),
      size.height - size.height * total / top,
    );
    Path pathOf(List<int> totals) {
      final path = Path();
      for (final (day, total) in totals.indexed) {
        final p = point(day, total);
        day == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      return path;
    }

    final previousPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = previousColor.withValues(alpha: .6);
    for (final metric in pathOf(previous).computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 8) {
        canvas.drawPath(metric.extractPath(d, d + 4), previousPaint);
      }
    }

    canvas.drawPath(
      pathOf(current),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = currentColor,
    );
    if (current.isNotEmpty) {
      canvas.drawCircle(
        point(current.length - 1, current.last),
        5,
        Paint()..color = currentColor,
      );
    }
  }

  @override
  bool shouldRepaint(_LinesPainter old) =>
      old.current != current ||
      old.previous != previous ||
      old.currentColor != currentColor;
}
