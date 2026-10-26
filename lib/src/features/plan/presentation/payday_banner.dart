import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../routing/app_routes.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../application/plan_providers.dart';

/// Offers the payday checklist in the days after payday, until it is done
/// or put away. Shows nothing otherwise, so any screen can include it.
class PaydayBanner extends ConsumerWidget {
  const PaydayBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposal = ref.watch(paydayProvider).value;
    if (proposal == null || !proposal.shouldOffer) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final tasks = proposal.checklist.tasks;
    final done = tasks.where((t) => proposal.ticked.contains(t.key)).length;
    final amount = formatMoney(Money(proposal.payday.amountMinor));

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colors.brandSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
          leading: Icon(
            Icons.payments_outlined,
            color: theme.colorScheme.primary,
          ),
          title: Text(
            proposal.payday.fromMessage
                ? 'Payday: $amount landed'
                : 'Payday: split $amount',
          ),
          subtitle: Text(
            'Rent, debts, set-asides and savings. $done of ${tasks.length} '
            'done.',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.go(AppRoutes.payday),
        ),
      ),
    );
  }
}
