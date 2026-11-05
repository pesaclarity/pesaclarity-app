import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/quick_records_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/people/people.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/format/date_labels.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../../sales/presentation/records_sheets.dart';
import '../../security/application/balance_visibility.dart';
import '../application/people_providers.dart';
import '../application/statement_pdf.dart';
import 'people_screen.dart';

/// What the business owes one supplier, from Bought and Paid.
final supplierHistoryProvider = FutureProvider.family<List<StatementLine>, int>(
  (ref, debtId) async {
    ref.watch(ledgerChangesProvider);
    return ref
        .watch(quickRecordsRepositoryProvider)
        .supplierHistory(
          debtId,
          today: CalendarDate.local(ref.watch(clockProvider)()),
        );
  },
);

/// A customer's statement: what they owe, how to collect it, and every
/// credit sale and payment.
class CustomerStatementScreen extends ConsumerWidget {
  const CustomerStatementScreen({required this.name, super.key});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final customers = ref.watch(customersProvider).value;
    final c = customers
        ?.where((c) => c.name.toLowerCase() == name.trim().toLowerCase())
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (c != null)
            IconButton(
              key: const Key('statement-share'),
              tooltip: 'Share the statement (PDF)',
              icon: const Icon(Icons.ios_share),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref.read(statementSenderProvider).share(c);
                } on Object {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('The statement was not made. Try again.'),
                    ),
                  );
                }
              },
            ),
        ],
      ),
      body: customers == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : c == null
          ? const Center(child: Text('Nothing owed or paid yet.'))
          : _Statement(
              headline: 'Owes you',
              owedMinor: c.owedMinor,
              standing: customerStanding(c, today: today),
              history: c.history,
              actions: [
                Expanded(
                  child: FilledButton(
                    key: const Key('statement-got-paid'),
                    onPressed: c.owedMinor > 0
                        ? () => showGotPaidSheet(context, customer: c.name)
                        : null,
                    child: const Text('Got paid'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('statement-remind'),
                    onPressed: c.owedMinor > 0
                        ? () => remindCustomer(context, ref, c)
                        : null,
                    child: const Text('Remind'),
                  ),
                ),
              ],
            ),
    );
  }
}

/// A supplier's statement: what the business owes them, and every purchase
/// and payment.
class SupplierStatementScreen extends ConsumerWidget {
  const SupplierStatementScreen({required this.debtId, super.key});

  final int debtId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final suppliers = ref.watch(suppliersProvider).value;
    final s = suppliers?.where((s) => s.debt.id == debtId).firstOrNull;
    final history = ref.watch(supplierHistoryProvider(debtId)).value;
    final due = s?.nextDue;
    return Scaffold(
      appBar: AppBar(title: Text(s?.name ?? 'Supplier')),
      body: suppliers == null || history == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _Statement(
              headline: 'You owe',
              owedMinor: s?.owedMinor ?? 0,
              standing: due == null
                  ? ''
                  : due == today
                  ? 'Due today'
                  : 'Due ${dayLabel(due, thisYear: today.year)}',
              history: history,
              actions: [
                Expanded(
                  child: FilledButton(
                    key: const Key('statement-paid'),
                    onPressed: s == null
                        ? null
                        : () => showPaidSheet(context, debtId: debtId),
                    child: const Text('Paid'),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Statement extends ConsumerWidget {
  const _Statement({
    required this.headline,
    required this.owedMinor,
    required this.standing,
    required this.history,
    required this.actions,
  });

  final String headline;
  final int owedMinor;
  final String standing;
  final List<StatementLine> history;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final hidden = ref.watch(balancesHiddenProvider);
    String plain(int minor) =>
        hidden ? maskedDigits : formatMoney(Money(minor), withCurrency: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hidden
                      ? '${BaseCurrency.code} $maskedDigits'
                      : formatMoney(Money(owedMinor)),
                  style: AppTypography.amount(
                    size: 32,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (standing.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    standing,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(children: actions),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
          child: Text(
            'HISTORY',
            style: theme.textTheme.labelLarge!.copyWith(
              color: colors.textMuted,
              letterSpacing: 1,
            ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, line) in history.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  title: Text(line.label),
                  subtitle: Text(shortDate(line.date)),
                  trailing: Text(
                    line.amountMinor > 0
                        ? '+${plain(line.amountMinor)}'
                        : '-${plain(-line.amountMinor)}',
                    style: AppTypography.amount(
                      size: 16,
                      color: line.amountMinor < 0
                          ? colors.successText
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
