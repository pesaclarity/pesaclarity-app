import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/budget/safe_to_spend.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/feature_placeholder.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../application/safe_to_spend_provider.dart';

/// Home tab: how am I doing today?
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safeToSpend = ref.watch(safeToSpendTodayProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleHome,
          child: const Text('Home'),
        ),
        actions: [
          Semantics(
            identifier: SemanticIds.homeProfile,
            child: IconButton(
              tooltip: 'Profile',
              icon: const Icon(Icons.person_outline),
              onPressed: () => context.go(AppRoutes.profile),
            ),
          ),
        ],
      ),
      body: FeaturePlaceholder(
        hero: safeToSpend == null
            ? const HeroFigureCard(
                label: 'Safe to spend today',
                figure: 'KES —',
                caption:
                    'Shows once your messages have been read and Plan has '
                    'a day-to-day budget.',
              )
            : _SafeToSpendCard(safeToSpend),
        question: 'How am I doing today?',
        contents: [
          'Safe to spend today, with weekday and weekend limits',
          'Plan used and left this month, and runway',
          'Financial Health Index and its change',
          'Upcoming bills',
          'The + button to add a transaction or import a statement',
        ],
      ),
    );
  }
}

class _SafeToSpendCard extends StatelessWidget {
  const _SafeToSpendCard(this.result);

  final SafeToSpend result;

  @override
  Widget build(BuildContext context) {
    String kes(int minor) => formatMoney(Money(minor));

    final limits =
        'Weekdays ${kes(result.weekdayLimitMinor)}, '
        'weekends ${kes(result.weekendLimitMinor)}.';
    final String caption;
    if (result.isBudgetUsedUp) {
      caption = 'This month\'s day-to-day budget is used up.';
    } else if (result.overTodayMinor > 0) {
      caption = '${kes(result.overTodayMinor)} over today\'s limit. $limits';
    } else {
      caption = limits;
    }

    return HeroFigureCard(
      label: 'Safe to spend today',
      figure: kes(result.leftTodayMinor),
      caption: caption,
    );
  }
}
