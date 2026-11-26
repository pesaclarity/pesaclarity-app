import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../theme/pesa_colors.dart';
import '../../balances/application/balances_providers.dart';
import '../../balances/presentation/balance_text.dart';
import '../../balances/presentation/balances_screen.dart';

/// "Cash in hand is below zero — set what you have", while a cash account
/// that counts on hand holds less than nothing. Opens setting its balance.
class CashBelowZeroCard extends ConsumerWidget {
  const CashBelowZeroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final short = ref.watch(balancesOverviewProvider).value?.cashBelowZero;
    if (short == null || short.isEmpty) return const SizedBox.shrink();
    final colors = PesaColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          key: const Key('home-cash-below-zero'),
          leading: Icon(Icons.circle, size: 10, color: colors.warning),
          minLeadingWidth: 10,
          title: const Text(BalanceText.cashBelowZero),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: () => showAccountBalanceSheet(context, short.first),
        ),
      ),
    );
  }
}
