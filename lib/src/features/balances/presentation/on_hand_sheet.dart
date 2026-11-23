import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/database/app_database.dart';
import '../../../domain/accounts/mpesa_lines.dart';
import '../../../domain/goals/goals_aside.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/application/mpesa_lines_providers.dart';
import '../../activity/application/activity_providers.dart';
import '../../goals/application/goals_aside_providers.dart';
import '../../goals/presentation/goals_aside_text.dart';
import '../../spaces/application/money_between_spaces_providers.dart';
import '../application/balances_providers.dart';
import 'balance_text.dart';

/// What On hand adds up: each day-to-day account, less the rainy day fund
/// and what is set aside for goals.
Future<void> showOnHandSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  builder: (context) => const AmountsHiddenScope(child: OnHandSheet()),
);

class OnHandSheet extends ConsumerWidget {
  const OnHandSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final onHand = ref.watch(onHandProvider).value;
    final accounts = ref.watch(activityAccountsProvider).value ?? const {};
    if (onHand == null) return const SheetBody(children: []);
    final between = ref.watch(moneyBetweenSpacesProvider).value;
    final goalNames = [
      for (final g
          in ref.watch(goalsAsideProvider).value?.goals ?? const <GoalAside>[])
        if (g.asideMinor > 0) g.goal.name,
    ];
    String money(int minor) => shownMoney(context, minor);
    // The main M-Pesa line first among the lines, then the second.
    final lines = ref.watch(mpesaLinesProvider).value ?? MpesaLines.empty;
    final byLine = byLineOrder(lines, [
      for (final a in accounts.values)
        if (lineOfReference(a.reference) != null) a.id,
    ]);
    int order(Account? a, Account? b, int ia, int ib) =>
        a == null || b == null ? ia.compareTo(ib) : byLine(a, b);
    return SheetBody(
      title: BalanceText.onHandTitle(
        shownMoney(context, onHand.totalMinor, withCurrency: true),
      ),
      subtitle: BalanceText.startOfToday,
      children: [
        for (final (id, minor) in [
          for (final MapEntry(:key, :value) in onHand.byAccount.entries)
            (key, value),
        ]..sort((a, b) => order(accounts[a.$1], accounts[b.$1], a.$1, b.$1)))
          LabelValueRow(
            key: Key('on-hand-account-$id'),
            label: accounts[id]?.name ?? 'Account',
            value: money(minor),
          ),
        if (onHand.rainyDayMinor > 0)
          LabelValueRow(
            label: BalanceText.lessRainyDay,
            value: money(-onHand.rainyDayMinor),
          ),
        if (onHand.goalsAsideMinor > 0)
          LabelValueRow(
            key: const Key('on-hand-goals'),
            label: GoalsAsideText.setAsideForGoals,
            detail: goalNames.isEmpty ? null : goalNames.join(', '),
            value: money(-onHand.goalsAsideMinor),
          ),
        const Divider(),
        LabelValueRow(
          key: const Key('on-hand-total'),
          label: BalanceText.onHand,
          value: money(onHand.totalMinor),
          strong: true,
        ),
        const SizedBox(height: 8),
        Text(
          [
            if (onHand.fulizaOwedMinor > 0)
              '${BalanceText.fulizaTakenOff(money(onHand.fulizaOwedMinor))}.',
            BalanceText.savingsNotCounted,
            if (onHand.goalsWantedMinor > 0) GoalsAsideText.onHandNote,
            if (heldLine(
                  between?.heldBySpace ?? const {},
                  ref.watch(spaceNamesProvider),
                  (m) => shownMoney(context, m, withCurrency: true),
                )
                case final held?)
              (between?.notOwnMinor ?? 0) > 0
                  ? '$held. ${BalanceText.safeToSpendLeavesOut}'
                  : '$held.',
          ].join(' '),
          style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('on-hand-see-all'),
            onPressed: () {
              Navigator.pop(context);
              context.push(AppRoutes.balances);
            },
            child: const TrailingLink(BalanceText.seeAllBalances),
          ),
        ),
      ],
    );
  }
}
