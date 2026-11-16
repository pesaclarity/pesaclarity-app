import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/insights/first_insight.dart';
import '../../../domain/insights/leakage.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/figures.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../insights/application/insights_providers.dart';
import '../../sms/application/scan_range_provider.dart';
import '../../sms/domain/scan_range.dart';
import '../application/onboarding_controller.dart';

/// Onboarding, after the first scan: what the messages read show,
/// before any setup.
class FirstInsightScreen extends ConsumerWidget {
  const FirstInsightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insight = ref.watch(firstInsightProvider);
    void finish() => ref.read(onboardingControllerProvider.notifier).complete();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your money'),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            ...switch (insight) {
              AsyncData(:final value) => _figures(
                context,
                value,
                ref.watch(scanRangeProvider).value,
              ),
              AsyncError() => [
                const _Body('Your figures will show on Home and Insights.'),
              ],
              _ => [
                const _Body('Adding up your messages.'),
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

  List<Widget> _figures(
    BuildContext context,
    FirstInsight insight,
    ScanRange? range,
  ) {
    String amount(int minor) => shownMoney(context, minor);
    final share = insight.leakageShareBasisPoints;
    final count = insight.transactionCount;
    return [
      Text(
        firstInsightTitle(range),
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 8),
      _Body(
        count == 1
            ? 'From 1 transaction in your messages.'
            : 'From $count transactions in your messages.',
      ),
      const SizedBox(height: 20),
      _Figure(label: 'Money in', value: amount(insight.incomeMinor)),
      const SizedBox(height: 12),
      _Figure(
        label: 'Spent, with fees',
        value: amount(insight.spendingMinor),
        note: insight.incomeMinor > 0
            ? _vsIncome(insight.spendingMinor, insight.incomeMinor, amount)
            : null,
      ),
      const SizedBox(height: 12),
      _Figure(
        label: 'Leakages',
        value: amount(insight.leakageMinor),
        note: share == null ? null : '${percentLabel(share)} of income',
        highlight: true,
      ),
      const SizedBox(height: 12),
      _Figure(
        label: 'Fuliza fees',
        value: amount(insight.fulizaFeesMinor),
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

String _vsIncome(int spending, int income, String Function(int) amount) {
  final gap = income - spending;
  if (gap >= 0) return '${amount(gap)} less than came in';
  return '${amount(-gap)} more than came in';
}

/// A figure tile; [highlight] outlines it and colours its note, for a
/// figure worth a look such as leakages.
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
    if (!highlight) {
      return MergeSemantics(
        child: FigureTile(label: label, value: value, note: note),
      );
    }
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
        side: BorderSide(color: colors.warning.withValues(alpha: .3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
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
                style: AppTypography.tileFigure(theme.colorScheme.onSurface),
              ),
              if (note != null) ...[
                const SizedBox(height: 4),
                Text(
                  note!,
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colors.warning,
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

/// "Your last 3 months", "Since 5 Mar 2026" or, for every message,
/// "Everything so far".
String firstInsightTitle(ScanRange? range) => switch (range?.period) {
  null || ScanPeriod.all => 'Everything so far',
  ScanPeriod.since => 'Since ${range!.label.substring('From '.length)}',
  _ => 'Your ${range!.label.toLowerCase()}',
};
