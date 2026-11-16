import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../application/balances_providers.dart';
import 'balance_text.dart';

/// What On hand adds up: each day-to-day account, less the rainy day fund.
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
    String money(int minor) => shownMoney(context, minor);
    return SheetBody(
      title: BalanceText.onHandTitle(
        shownMoney(context, onHand.totalMinor, withCurrency: true),
      ),
      subtitle: BalanceText.startOfToday,
      children: [
        for (final MapEntry(key: id, value: minor) in onHand.byAccount.entries)
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
