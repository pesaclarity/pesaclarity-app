import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/app_routes.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/layout.dart';
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
    final tasks = proposal.checklist.tasks;
    final done = tasks.where((t) => proposal.ticked.contains(t.key)).length;
    final amount = shownMoney(context, proposal.payday.amountMinor);

    return Padding(
      padding: const EdgeInsets.only(bottom: Layout.cardGap),
      child: Card(
        child: ListTile(
          leading: const IconBadge(Icons.payments_outlined),
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
