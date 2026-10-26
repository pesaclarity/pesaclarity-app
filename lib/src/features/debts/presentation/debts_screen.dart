import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/debts/payoff_plan.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/feature_placeholder.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../application/debt_plan_provider.dart';

export '../../../domain/time/date_labels.dart' show monthLabel;

/// Debts, one level under Goals: when will I be debt-free?
class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(debtPlanProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleDebts,
          child: const Text('Debts'),
        ),
      ),
      body: FeaturePlaceholder(
        hero: plan == null
            ? const HeroFigureCard(
                label: 'Debt-free by',
                figure: '—',
                caption: 'Shows once you add a debt.',
              )
            : _DebtFreeCard(plan),
        question: 'When will I be debt-free?',
        contents: const [
          'Remaining balance across every debt, family loans included',
          'Payoff strategy: avalanche, snowball or custom',
          "This payday's split",
          'Fuliza tracker: draws, fees and days overdrawn',
          'What-if slider',
        ],
      ),
    );
  }
}

class _DebtFreeCard extends StatelessWidget {
  const _DebtFreeCard(this.comparison);

  final PayoffComparison comparison;

  @override
  Widget build(BuildContext context) {
    final month = comparison.plan.debtFreeMonth;
    if (month == null) {
      return const HeroFigureCard(
        label: 'Debt-free by',
        figure: 'Not yet',
        caption:
            'At these payments a debt never clears. Paying more each month '
            'brings a date.',
      );
    }
    final saved = comparison.interestSavedMinor;
    return HeroFigureCard(
      label: 'Debt-free by',
      figure: monthLabel(month),
      caption: saved == null || saved <= 0
          ? null
          : '${formatMoney(Money(saved))} less interest than minimums only.',
    );
  }
}
