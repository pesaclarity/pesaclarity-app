import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/balances_providers.dart';
import 'balance_text.dart';

/// The amber line under Home's lead card, shown only while an account's
/// latest reported balance does not add up.
class BalanceWarningLine extends ConsumerWidget {
  const BalanceWarningLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final off = ref.watch(balancesOverviewProvider).value?.off ?? const [];
    if (off.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final account = off.first;
    final gap = account.check.latestGap!;
    return Padding(
      padding: const EdgeInsets.only(top: Layout.cardGap),
      child: Material(
        color: colors.warningSoft,
        borderRadius: BorderRadius.circular(Layout.panelRadius),
        child: InkWell(
          key: const Key('home-balance-warning'),
          borderRadius: BorderRadius.circular(Layout.panelRadius),
          onTap: () => context.push(AppRoutes.balanceCheck),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Layout.cardPadding,
              vertical: 12,
            ),
            child: Row(
              children: [
                const IconBadge(Icons.priority_high),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        BalanceText.doesNotAddUp(account.account.name),
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        BalanceText.unaccounted(
                          shownMoney(
                            context,
                            gap.gapMinor.abs(),
                            withCurrency: true,
                          ),
                          dayHeading(gap.from.date, today: today),
                        ),
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const TrailingLink(BalanceText.check),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Warnings at the top of Messages to check: each account whose new
/// reported balance does not match what the app worked out.
class BalanceWarningCards extends ConsumerWidget {
  const BalanceWarningCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final off = ref.watch(balancesOverviewProvider).value?.off ?? const [];
    if (off.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    return Column(
      children: [
        for (final account in off)
          Card(
            child: InkWell(
              key: Key('review-balance-warning-${account.account.id}'),
              onTap: () => context.push(AppRoutes.balanceCheck),
              child: Padding(
                padding: const EdgeInsets.all(Layout.cardPadding),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const IconBadge(Icons.priority_high),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            BalanceText.doesNotAddUp(account.account.name),
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            BalanceText.unaccountedBetween(
                              shownMoney(
                                context,
                                account.check.latestGap!.gapMinor.abs(),
                                withCurrency: true,
                              ),
                              dayHeading(
                                account.check.latestGap!.from.date,
                                today: today,
                              ),
                              dayHeading(
                                account.check.latestGap!.to.date,
                                today: today,
                              ),
                            ),
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const TrailingLink(BalanceText.seeTheGap),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
