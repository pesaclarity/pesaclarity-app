import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/ledger/not_yet_sorted.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../theme/pesa_colors.dart';
import '../application/not_yet_sorted_provider.dart';

/// "KES 12,400 not yet sorted", with what makes it up under it, while any
/// money in waits for a name or any message waits to be checked. Balance
/// gaps are not part of it: they have their own warning line.
class NotYetSortedCard extends ConsumerWidget {
  const NotYetSortedCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sorted = ref.watch(notYetSortedProvider).value;
    if (sorted == null || sorted.isEmpty) return const SizedBox.shrink();
    final colors = PesaColors.of(context);
    final parts = sorted.parts;
    // With no amount known, as when no message could be read, the parts
    // are the title.
    final title = sorted.hasAmount
        ? '${shownMoney(context, sorted.amountMinor, withCurrency: true)} '
              'not yet sorted'
        : parts.join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          key: const Key('home-review'),
          leading: Icon(Icons.circle, size: 10, color: colors.warning),
          minLeadingWidth: 10,
          title: Text(title),
          subtitle: sorted.hasAmount ? Text(parts.join(' · ')) : null,
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: () => _open(context, sorted),
        ),
      ),
    );
  }

  /// Messages first, since checking them may name people too; otherwise
  /// the money in that waits for a name.
  void _open(BuildContext context, NotYetSorted sorted) {
    if (sorted.messagesToCheck > 0) {
      context.push(AppRoutes.review);
      return;
    }
    context.go(
      AppRoutes.activityWith(
        ActivityFilter(type: ActivityType.moneyIn, from: sorted.firstNotNamed),
      ),
    );
  }
}
