import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../domain/budget/budget_alerts.dart';
import '../../../domain/reminders/reminder_settings.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../theme/pesa_colors.dart';
import '../../reminders/application/reminders_controller.dart';
import '../../reminders/presentation/budget_share.dart';
import '../application/budget_alert_providers.dart';

String _kes(BuildContext context, int minor) =>
    shownMoney(context, minor, withCurrency: true);

String _plain(BuildContext context, int minor) => shownMoney(context, minor);

String _daysLeft(int days) => days == 1 ? '1 day left' : '$days days left';

/// The card's title and the line under it. In Plan a nearing category at
/// the share for all leads with its amounts; elsewhere with the alert.
(String, String) budgetAlertCardText(
  BuildContext context,
  BudgetAlert alert, {
  required bool inPlan,
}) {
  final used =
      '${_kes(context, alert.usedMinor)} of '
      '${_plain(context, alert.plannedMinor)}';
  final left = _daysLeft(alert.daysLeft);
  if (alert.level == BudgetAlertLevel.over) {
    return (
      budgetAlertTitle(alert),
      '$used used · ${_plain(context, alert.overMinor)} over, $left',
    );
  }
  if (alert.ownShare) {
    return (
      budgetAlertTitle(alert),
      '$used · warns at ${alert.percent}%, its own · $left',
    );
  }
  if (inPlan) {
    final perDay = alert.perDayMinor;
    return (
      '${alert.name}: $used used',
      [
        left,
        if (perDay != null)
          'about ${_plain(context, perDay)} a day keeps it in plan',
      ].join(' · '),
    );
  }
  return (budgetAlertTitle(alert), '$used · $left');
}

/// One budget alert: an amber dot, what it says, and a way in.
class BudgetAlertCard extends StatelessWidget {
  const BudgetAlertCard(
    this.alert, {
    required this.inPlan,
    required this.onTap,
    super.key,
  });

  final BudgetAlert alert;
  final bool inPlan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    final (title, subtitle) = budgetAlertCardText(
      context,
      alert,
      inPlan: inPlan,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          key: Key('budget-alert-${alert.categoryId}'),
          leading: Icon(Icons.circle, size: 10, color: colors.warning),
          minLeadingWidth: 10,
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Plan's budget alerts, at the top of this month.
class PlanBudgetAlerts extends ConsumerWidget {
  const PlanBudgetAlerts({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(budgetAlertsProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final alert in alerts)
          BudgetAlertCard(
            alert,
            inPlan: true,
            onTap: () => showCategoryAlertSheet(
              context,
              categoryId: alert.categoryId,
              name: alert.name,
              usedMinor: alert.usedMinor,
              plannedMinor: alert.plannedMinor,
            ),
          ),
      ],
    );
  }
}

/// The most pressing budget alert on Home, which opens Plan.
class HomeBudgetAlertCard extends ConsumerWidget {
  const HomeBudgetAlertCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = ref.watch(budgetAlertsProvider).value?.firstOrNull;
    if (alert == null) return const SizedBox.shrink();
    return BudgetAlertCard(
      alert,
      key: const Key('home-budget-alert'),
      inPlan: false,
      onTap: () => context.go(AppRoutes.plan),
    );
  }
}

/// The menu choice for the share set in Profile.
const _sameAsAll = -1;

/// A Plan category's own "Warn me at": the share for all, one of its own,
/// or off.
Future<void> showCategoryAlertSheet(
  BuildContext context, {
  required int categoryId,
  required String name,
  required int usedMinor,
  required int plannedMinor,
}) => showAppSheet<void>(
  context: context,
  builder: (context) => _CategoryAlertSheet(
    categoryId: categoryId,
    name: name,
    usedMinor: usedMinor,
    plannedMinor: plannedMinor,
  ),
);

class _CategoryAlertSheet extends ConsumerWidget {
  const _CategoryAlertSheet({
    required this.categoryId,
    required this.name,
    required this.usedMinor,
    required this.plannedMinor,
  });

  final int categoryId;
  final String name;
  final int usedMinor;
  final int plannedMinor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings =
        ref.watch(remindersControllerProvider).value ??
        const ReminderSettings();
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final all = settings.budgetAlertPercent;
    final own = settings.budgetAlertCategoryPercents[categoryId];
    final value = own ?? _sameAsAll;
    final note = switch (own) {
      null =>
        'Same as all: uses the share set in Profile › Reminders, now $all%.',
      ReminderSettings.budgetAlertOff => 'Off: no budget alerts for $name.',
      _ =>
        'Its own share: $name warns at $own%, whatever the share in '
            'Profile.',
    };
    final options = [
      (_sameAsAll, 'Same as all ($all%)'),
      ...shareChoices(own ?? all, markDefault: false),
      (ReminderSettings.budgetAlertOff, 'Off'),
    ];

    void choose(int chosen) => ref
        .read(remindersControllerProvider.notifier)
        .change(
          (s) => s.withCategoryPercent(
            categoryId,
            chosen == _sameAsAll ? null : chosen,
          ),
        );

    return SheetBody(
      title: name,
      subtitle:
          '${_kes(context, usedMinor)} of ${_plain(context, plannedMinor)} '
          'used in ${monthName(today.yearMonth).substring(0, 3)} · '
          '${_daysLeft(today.yearMonth.dayCount - today.day + 1)}',
      children: [
        Card(
          child: ChoiceTile<int>(
            title: const Text('Warn me at'),
            trailing: shareMenu(
              context,
              key: const Key('category-warn-at'),
              options: options,
              value: value,
              onChanged: choose,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(note, style: theme.textTheme.bodySmall),
        if (!settings.budgetAlerts) ...[
          const SizedBox(height: 8),
          Text(
            'Budget alerts are off in Profile › Reminders.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
