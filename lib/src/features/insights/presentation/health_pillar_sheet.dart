import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/health/health_index.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/pesa_colors.dart';
import '../application/insights_report.dart';
import '../application/month_labels.dart';

/// Points as shown to a person: whole numbers, or one decimal.
String pointsLabel(int centipoints) {
  final tenths = (centipoints + 5) ~/ 10;
  return tenths % 10 == 0
      ? '${tenths ~/ 10}'
      : '${tenths ~/ 10}.${tenths % 10}';
}

/// One pillar of the Financial Health Index: its two indicators, their
/// points and what would bring each to full marks.
Future<void> showHealthPillar(
  BuildContext context,
  HealthIndex index,
  HealthPillar pillar,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => HealthPillarSheet(index: index, pillar: pillar),
);

class HealthPillarSheet extends StatelessWidget {
  const HealthPillarSheet({
    required this.index,
    required this.pillar,
    super.key,
  });

  final HealthIndex index;
  final HealthPillar pillar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final month = index.month;
    final scores = [
      for (final s in index.indicators)
        if (s.indicator.pillar == pillar) s,
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(pillar.label, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '${pillarPoints(index, pillar)} of 25 points in '
              '${monthName(month)}',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            for (final s in scores) ...[
              const Divider(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.indicator.label,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  Text(
                    '${pointsLabel(s.centipoints)} of '
                    '${pointsLabel(indicatorMaxCentipoints)}',
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: s.centipoints / indicatorMaxCentipoints,
                  minHeight: 8,
                  color: theme.colorScheme.primary,
                  backgroundColor: colors.border,
                ),
              ),
              const SizedBox(height: 8),
              if (index.actionFor(s.indicator) case final action?)
                Text(action.message, style: theme.textTheme.bodyMedium)
              else
                Text(
                  'Full marks',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.successText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
            const SizedBox(height: 16),
            Text(
              'Each pillar is worth 25 points, two indicators of '
              '${pointsLabel(indicatorMaxCentipoints)}.',
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('pillar-transactions'),
              onPressed: () {
                Navigator.pop(context);
                context.go(
                  AppRoutes.activityWith(
                    ActivityFilter(from: month.firstDay, to: month.lastDay),
                  ),
                );
              },
              child: Text("See ${monthName(month)}'s transactions"),
            ),
          ],
        ),
      ),
    );
  }
}
