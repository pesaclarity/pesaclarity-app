import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/budget/safe_to_spend.dart';
import '../../../domain/forecast/cash_flow_forecast.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/feature_placeholder.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../theme/app_typography.dart';
import '../../security/application/balance_visibility.dart';
import '../application/cash_flow_forecast_provider.dart';
import '../application/health_index_provider.dart';
import '../application/safe_to_spend_provider.dart';

/// Home tab: how am I doing today?
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safeToSpend = ref.watch(safeToSpendTodayProvider).value;
    final health = ref.watch(healthIndexProvider).value;
    final forecast = ref.watch(cashFlowForecastProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.go(AppRoutes.profile),
          ),
        ],
      ),
      body: FeaturePlaceholder(
        hero: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (safeToSpend == null)
              const HeroFigureCard(
                label: 'Safe to spend today',
                figure: 'KES —',
                caption:
                    'Shows once your messages have been read and Plan has '
                    'a day-to-day budget.',
              )
            else
              _SafeToSpendCard(safeToSpend),
            if (forecast != null) ...[
              const SizedBox(height: 16),
              _ForecastCard(forecast),
            ],
            if (health != null) ...[
              const SizedBox(height: 16),
              _HealthIndexCard(health),
            ],
          ],
        ),
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

class _HealthIndexCard extends StatelessWidget {
  const _HealthIndexCard(this.health);

  final HealthOnHome health;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = health.change;
    final String trend;
    if (change == null) {
      trend = '';
    } else if (change > 0) {
      trend = ' Up $change on the month before.';
    } else if (change < 0) {
      trend = ' Down ${-change} on the month before.';
    } else {
      trend = ' Same as the month before.';
    }

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: const Text('Financial Health Index'),
        subtitle: Text('${health.index.band.label}.$trend'),
        trailing: Text(
          '${health.index.score}',
          style: AppTypography.amount(
            size: 32,
            color: theme.colorScheme.onSurface,
          ),
        ),
        // TODO(health): open the weakest pillar and bestAction on tap.
      ),
    );
  }
}

class _ForecastCard extends ConsumerWidget {
  const _ForecastCard(this.forecast);

  final CashFlowForecast forecast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(balancesHiddenProvider);
    final messages = [
      for (final message in forecast.messages) maskAmountsIf(hidden, message),
    ];
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Text(messages.first),
        subtitle: messages.length > 1
            ? Text(messages.skip(1).join('\n'))
            : null,
      ),
    );
  }
}
