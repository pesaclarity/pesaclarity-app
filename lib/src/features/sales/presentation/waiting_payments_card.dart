import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/sales/sale_matching.dart';
import '../../../shared/format/date_labels.dart';
import '../../../theme/pesa_colors.dart';
import '../application/sales_providers.dart';
import 'pay_sheet.dart';

/// Sales on Today whose M-Pesa or bank payment has not come in yet. Each
/// matches on its own when the message arrives.
class WaitingPaymentsCard extends ConsumerWidget {
  const WaitingPaymentsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = ref.watch(waitingPaymentsProvider).value ?? const [];
    if (waiting.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final controller = ref.read(salesControllerProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('waiting-payments'),
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
              child: Text(
                'Waiting for payment',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Each one matches on its own when the message comes.',
                style: theme.textTheme.bodySmall!.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ),
            for (final w in waiting)
              ListTile(
                key: Key('waiting-${w.kind.name}-${w.id}'),
                title: Text(waitingTitle(w)),
                subtitle: Text(
                  [
                    switch (w.kind) {
                      WaitingKind.sale => w.note ?? 'Other sale',
                      WaitingKind.bought => w.note ?? 'Bought',
                      WaitingKind.gotPaid => 'What they owe',
                      WaitingKind.paid => 'What you owe',
                    },
                    formatTime(w.at),
                  ].join(' · '),
                ),
                trailing: PopupMenuButton<_Choice>(
                  tooltip: 'More',
                  onSelected: (choice) => switch (choice) {
                    _Choice.cash => controller.paidInCash(w),
                    _Choice.remove => _confirmRemove(context, controller, w),
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: _Choice.cash,
                      child: Text('It was paid in cash'),
                    ),
                    PopupMenuItem(
                      value: _Choice.remove,
                      child: Text('Remove it'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    SalesController controller,
    WaitingPayment payment,
  ) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this?'),
        content: Text(
          payment.kind == WaitingKind.sale
              ? "It comes off today's sales."
              : 'It comes off your records.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove == true) await controller.removeWaiting(payment);
  }
}

enum _Choice { cash, remove }

/// What a waiting payment is, in a line: `KES 180 sale by M-Pesa`,
/// `Otieno paid KES 1,200 by M-Pesa`.
String waitingTitle(WaitingPayment w) {
  final amount = formatMoney(Money(w.amountMinor, currency: w.currency));
  final how = methodName(w.method);
  final who = w.party;
  return switch (w.kind) {
    WaitingKind.sale => '$amount sale by $how',
    WaitingKind.bought =>
      who == null ? '$amount bought by $how' : '$amount to $who by $how',
    WaitingKind.gotPaid => '${who ?? 'A customer'} paid $amount by $how',
    WaitingKind.paid => 'Paid ${who ?? 'a supplier'} $amount by $how',
  };
}
