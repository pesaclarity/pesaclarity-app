import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/insights/first_insight.dart';
import '../../../domain/insights/leakage.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../../insights/application/insights_providers.dart';
import '../application/onboarding_controller.dart';

/// Onboarding, after the first scan: what the last 90 days of messages show,
/// before any setup.
class FirstInsightScreen extends ConsumerWidget {
  const FirstInsightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(firstInsightProvider);
    void finish() => ref.read(onboardingControllerProvider.notifier).complete();

    return Scaffold(
      appBar: AppBar(title: const Text('Your money')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            ...switch (insight) {
              AsyncData(:final value) => _figures(context, value),
              AsyncError() => [
                const _Body('Your figures will show on Home and Insights.'),
              ],
              _ => [
                const _Body('Adding up your last $firstInsightDays days.'),
                const SizedBox(height: 16),
                const LinearProgressIndicator(semanticsLabel: 'Adding up'),
              ],
            },
            const SizedBox(height: 24),
            FilledButton(onPressed: finish, child: const Text('Go to Home')),
          ],
        ),
      ),
    );
  }

  List<Widget> _figures(BuildContext context, FirstInsight insight) {
    String kes(int minor) => formatMoney(Money(minor));
    final share = insight.leakageShareBasisPoints;
    final count = insight.transactionCount;
    return [
      Text(
        'Your last $firstInsightDays days',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      _Body(
        count == 1
            ? 'From 1 transaction in your messages.'
            : 'From $count transactions in your messages.',
      ),
      const SizedBox(height: 20),
      _Figure(label: 'Money in', value: kes(insight.incomeMinor)),
      const SizedBox(height: 12),
      _Figure(
        label: 'Spent, with fees',
        value: kes(insight.spendingMinor),
        note: insight.incomeMinor > 0
            ? _vsIncome(insight.spendingMinor, insight.incomeMinor, kes)
            : null,
      ),
      const SizedBox(height: 12),
      _Figure(
        label: 'Leakages',
        value: kes(insight.leakageMinor),
        note: share == null ? null : '${percentLabel(share)} of income',
        highlight: true,
      ),
      const SizedBox(height: 12),
      _Figure(
        label: 'Fuliza fees',
        value: kes(insight.fulizaFeesMinor),
        note: switch (insight.fulizaDays) {
          0 => 'Clear of Fuliza',
          1 => 'Fuliza used on 1 day',
          final n => 'Fuliza used on $n days',
        },
        highlight: insight.fulizaFeesMinor > 0,
      ),
      const SizedBox(height: 20),
      const _Body(
        'Leakages are fees plus money to people and places you mark as '
        'lifestyle, friends or family. Name the numbers and tills you pay '
        'to see where the rest goes.',
      ),
    ];
  }
}

String _vsIncome(int spending, int income, String Function(int) kes) {
  final gap = income - spending;
  if (gap >= 0) return '${kes(gap)} less than came in';
  return '${kes(-gap)} more than came in';
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.note,
    this.highlight = false,
  });

  final String label;
  final String value;
  final String? note;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      shape: highlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: .3),
              ),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTypography.amount(
                  size: 28,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (note != null) ...[
                const SizedBox(height: 4),
                Text(
                  note!,
                  style: theme.textTheme.labelLarge!.copyWith(
                    color: highlight
                        ? theme.colorScheme.primary
                        : colors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyLarge!
        .copyWith(color: PesaColors.of(context).textMuted),
  );
}
