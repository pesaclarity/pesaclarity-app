import 'package:flutter/material.dart';

import '../../../shared/widgets/amounts_hidden.dart';
import '../../../theme/pesa_colors.dart';
import '../../insights/presentation/spending_charts_card.dart';
import '../domain/slm_answer.dart';

String _title(SlmChoice c) {
  final what = switch (c.data) {
    SlmData.top_categories => 'Spending by category',
    SlmData.top_payees => 'Top payees',
    SlmData.in_out_weeks => 'Money in and out by week',
    SlmData.budget_vs_spent => 'Budgets: spent and planned',
    SlmData.months_trend => 'Spending by month',
    SlmData.fees => 'Fees and other spending',
    SlmData.none => '',
  };
  final when = switch (c.period) {
    SlmPeriod.since_payday => 'since payday',
    SlmPeriod.this_month => 'this month',
    SlmPeriod.last_3_months => 'last 3 months',
  };
  return c.data == SlmData.months_trend ? what : '$what, $when';
}

/// The chart the model picked, drawn with the app's chart colours and ring
/// from [points] the app worked out. Nothing here comes from the model but
/// the choice of chart.
class SlmChartView extends StatelessWidget {
  const SlmChartView({required this.choice, required this.points, super.key});

  final SlmChoice choice;
  final List<SlmPoint> points;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final series = chartSeries(context);
    final colors = PesaColors.of(context);
    if (points.isEmpty || points.every((p) => p.amountMinor <= 0)) {
      return const SizedBox.shrink();
    }
    final Widget chart;
    if (choice.chart == SlmChart.donut) {
      final shown = [
        for (final p in points)
          if (p.amountMinor > 0) p,
      ];
      final total = shown.fold(0, (s, p) => s + p.amountMinor);
      chart = Row(
        children: [
          SizedBox.square(
            dimension: 96,
            child: CustomPaint(
              key: const Key('slm-chart-ring'),
              painter: SpendingRingPainter(
                fractions: [for (final p in shown) p.amountMinor / total],
                colors: [
                  for (var i = 0; i < shown.length; i++)
                    series[i % series.length],
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, p) in shown.indexed)
                  _Legend(
                    color: series[i % series.length],
                    label: p.label,
                    amount: shownMoney(context, p.amountMinor),
                  ),
              ],
            ),
          ),
        ],
      );
    } else {
      // Bars (and a month-by-month line as bars, latest highlighted).
      final largest = points.fold(0, (m, p) {
        final x = p.amountMinor > (p.secondMinor ?? 0)
            ? p.amountMinor
            : (p.secondMinor ?? 0);
        return x > m ? x : m;
      });
      double f(int v) => largest <= 0 || v <= 0 ? 0 : v / largest;
      final two = points.any((p) => p.secondMinor != null);
      chart = Column(
        key: const Key('slm-chart-bars'),
        children: [
          for (final (i, p) in points.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.label,
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        shownMoney(context, p.amountMinor),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  _Bar(
                    fraction: f(p.amountMinor),
                    color: choice.data == SlmData.months_trend
                        ? (i == points.length - 1 ? colors.link : colors.border)
                        : series[0],
                  ),
                  if (p.secondMinor != null) ...[
                    const SizedBox(height: 2),
                    _Bar(fraction: f(p.secondMinor!), color: series[1]),
                  ],
                ],
              ),
            ),
          if (two)
            Row(
              children: [
                _Legend(
                  color: series[0],
                  label: switch (choice.data) {
                    SlmData.budget_vs_spent => 'Spent',
                    SlmData.in_out_weeks => 'Money in',
                    _ => 'Spent',
                  },
                ),
                const SizedBox(width: 12),
                _Legend(
                  color: series[1],
                  label: switch (choice.data) {
                    SlmData.budget_vs_spent => 'Planned',
                    SlmData.in_out_weeks => 'Spent',
                    _ => 'Money in',
                  },
                ),
              ],
            ),
        ],
      );
    }
    return Padding(
      key: const Key('slm-chart'),
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_title(choice), style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          chart,
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(4),
    child: SizedBox(
      height: 8,
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.02, 1.0),
          heightFactor: 1,
          child: ColoredBox(color: color),
        ),
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.amount});

  final Color color;
  final String label;
  final String? amount;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: amount == null ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          if (amount == null)
            Text(label, style: style)
          else ...[
            Expanded(
              child: Text(label, style: style, overflow: TextOverflow.ellipsis),
            ),
            Text(amount!, style: style),
          ],
        ],
      ),
    );
  }
}
