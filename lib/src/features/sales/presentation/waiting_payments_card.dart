import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/sales/sale_matching.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../application/sales_providers.dart';
import 'choose_payments_sheet.dart';
import 'pay_sheet.dart';

/// Sales on Today whose M-Pesa or bank payment has not come in yet. Each
/// matches on its own when the message arrives; tapping one offers what
/// else to do with it.
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
              child: Text(
                'Waiting for payment',
                style: theme.textTheme.titleMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Each one matches on its own when the message comes.',
                style: theme.textTheme.bodySmall!.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ),
            for (final w in waiting) ...[
              const Divider(height: 1),
              ListTile(
                key: Key('waiting-${w.kind.name}-${w.id}'),
                onTap: () => _choose(context, controller, w),
                title: Text(waitingTitle(w)),
                subtitle: Text(_detail(w)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      shownMoney(context, w.amountMinor, currency: w.currency),
                      style: AppTypography.rowAmount(
                        theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: colors.textMuted),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// A small sheet with what can be done with [payment]: choose its
  /// payments (a sale can be paid by payments of other amounts), say it
  /// was paid in cash, or delete it.
  Future<void> _choose(
    BuildContext context,
    SalesController controller,
    WaitingPayment payment,
  ) async {
    final amount = shownMoney(
      context,
      payment.amountMinor,
      currency: payment.currency,
    );
    final choice = await showAppSheet<_Choice>(
      context: context,
      builder: (context) {
        final error = Theme.of(context).colorScheme.error;
        return SheetBody(
          title: waitingTitle(payment),
          subtitle: '$amount · ${_detail(payment)}',
          children: [
            if (payment.kind == WaitingKind.sale)
              ListTile(
                key: const Key('waiting-choose'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.checklist_outlined),
                title: const Text('Choose payments'),
                subtitle: const Text('When it came in parts or another amount'),
                onTap: () => Navigator.pop(context, _Choice.choose),
              ),
            ListTile(
              key: const Key('waiting-cash'),
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.payments_outlined),
              title: const Text('It was paid in cash'),
              onTap: () => Navigator.pop(context, _Choice.cash),
            ),
            ListTile(
              key: const Key('waiting-delete'),
              contentPadding: EdgeInsets.zero,
              iconColor: error,
              textColor: error,
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete it'),
              onTap: () => Navigator.pop(context, _Choice.remove),
            ),
          ],
        );
      },
    );
    if (!context.mounted) return;
    switch (choice) {
      case _Choice.choose:
        await showChoosePaymentsSheet(context, payment);
      case _Choice.cash:
        await controller.paidInCash(payment);
      case _Choice.remove:
        await _confirmRemove(context, controller, payment);
      case null:
        break;
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    SalesController controller,
    WaitingPayment payment,
  ) async {
    final sale = payment.kind == WaitingKind.sale;
    final remove = await confirmDelete(
      context,
      title: sale ? 'Delete this sale?' : 'Delete this record?',
      body: sale ? "It comes off today's sales." : 'It comes off your records.',
    );
    if (remove) await controller.removeWaiting(payment);
  }
}

enum _Choice { choose, cash, remove }

/// What it was for and when: `Avocados · 14:30`.
String _detail(WaitingPayment w) => [
  switch (w.kind) {
    WaitingKind.sale => w.note ?? 'Other sale',
    WaitingKind.bought => w.note ?? 'Bought',
    WaitingKind.gotPaid => 'What they owe',
    WaitingKind.paid => 'What you owe',
    WaitingKind.paidYourself => 'Pay yourself',
    WaitingKind.payFromBusiness => 'From your business',
    WaitingKind.change => 'Change',
  },
  formatTime(w.at),
].join(' · ');

/// What a waiting payment is, in a line: `Sale by M-Pesa`, `Otieno paid by
/// M-Pesa`. Its amount shows at the end of its row.
String waitingTitle(WaitingPayment w) {
  final how = methodName(w.method);
  final who = w.party;
  return switch (w.kind) {
    WaitingKind.sale => 'Sale by $how',
    WaitingKind.bought => who == null ? 'Bought by $how' : 'To $who by $how',
    WaitingKind.gotPaid => '${who ?? 'A customer'} paid by $how',
    WaitingKind.paid => 'Paid ${who ?? 'a supplier'} by $how',
    WaitingKind.paidYourself => 'Paid yourself by $how',
    WaitingKind.payFromBusiness => 'From your business by $how',
    WaitingKind.change =>
      who == null ? 'Change by $how' : 'Change to $who by $how',
  };
}
