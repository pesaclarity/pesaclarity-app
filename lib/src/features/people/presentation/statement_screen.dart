import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/quick_records_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/people/people.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../printing/presentation/print_sheet.dart';
import '../../sales/presentation/records_sheets.dart';
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
    final loaded = ref.watch(customersProvider);
    final customers = loaded.value;
    final c = customers
        ?.where((c) => c.name.toLowerCase() == name.trim().toLowerCase())
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          if (c != null)
            IconButton(
              key: const Key('statement-print'),
              tooltip: 'Print the statement',
              icon: const Icon(Icons.print_outlined),
              onPressed: () {
                final sender = ref.read(statementSenderProvider);
                showPrintSheet(
                  context,
                  title: 'Print statement',
                  subtitle: c.name,
                  name: sender.fileName(c),
                  pdf: () => sender.pdf(c),
                  fullPage: true,
                );
              },
            ),
          if (c != null)
            IconButton(
              key: const Key('statement-share'),
              tooltip: 'Share the statement (PDF)',
              icon: const Icon(Icons.ios_share),
              onPressed: () async {
                try {
                  await ref.read(statementSenderProvider).share(c);
                } on Object {
                  if (context.mounted) {
                    showNote(context, 'The statement was not made. Try again.');
                  }
                }
              },
            ),
          const AmountsEye(),
          const SizedBox(width: 8),
        ],
      ),
      body: loaded.hasError && !loaded.hasValue
          ? ErrorView(
              'This statement could not load.',
              onRetry: () => ref.invalidate(customersProvider),
            )
          : customers == null
          ? const LoadingView()
          : c == null
          ? ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: const [
                EmptyNote('Credit sales and payments show here.'),
              ],
            )
          : _Statement(
              headline: 'Owes you',
              owedMinor: c.owedMinor,
              standing: customerStanding(c, today: today),
              history: c.history,
              actions: ButtonPair(
                primary: FilledButton(
                  key: const Key('statement-got-paid'),
                  onPressed: c.owedMinor > 0
                      ? () => showGotPaidSheet(context, customer: c.name)
                      : null,
                  child: const Text('Got paid'),
                ),
                secondary: OutlinedButton(
                  key: const Key('statement-remind'),
                  onPressed: c.owedMinor > 0
                      ? () => remindCustomer(context, ref, c)
                      : null,
                  child: const Text('Remind'),
                ),
              ),
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
    final loadedSuppliers = ref.watch(suppliersProvider);
    final loadedHistory = ref.watch(supplierHistoryProvider(debtId));
    final suppliers = loadedSuppliers.value;
    final s = suppliers?.where((s) => s.debt.id == debtId).firstOrNull;
    final history = loadedHistory.value;
    final due = s?.nextDue;
    final failed =
        (loadedSuppliers.hasError && !loadedSuppliers.hasValue) ||
        (loadedHistory.hasError && !loadedHistory.hasValue);
    return Scaffold(
      appBar: AppBar(
        title: Text(s?.name ?? 'Supplier'),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: failed
          ? ErrorView(
              'This statement could not load.',
              onRetry: () {
                ref
                  ..invalidate(suppliersProvider)
                  ..invalidate(supplierHistoryProvider(debtId));
              },
            )
          : suppliers == null || history == null
          ? const LoadingView()
          : _Statement(
              headline: 'You owe',
              owedMinor: s?.owedMinor ?? 0,
              standing: due == null
                  ? ''
                  : due == today
                  ? 'Due today'
                  : 'Due ${dayLabel(due, thisYear: today.year)}',
              history: history,
              actions: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('statement-paid'),
                  onPressed: s == null
                      ? null
                      : () => showPaidSheet(context, debtId: debtId),
                  child: const Text('Paid'),
                ),
              ),
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

  /// The buttons under the figure: Got paid and Remind, or Paid.
  final Widget actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final hidden = AmountsHidden.of(context);
    String plain(int minor) =>
        moneyOrHidden(minor, hidden: hidden, withCurrency: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Layout.cardPadding),
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
                  moneyOrHidden(owedMinor, hidden: hidden),
                  style: AppTypography.headlineFigure(
                    theme.colorScheme.onSurface,
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
                actions,
              ],
            ),
          ),
        ),
        const SectionLabel('History'),
        Card(
          child: Column(
            children: [
              for (final (i, line) in history.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  title: Text(line.label),
                  subtitle: Text(shortDate(line.date)),
                  trailing: Text(
                    line.amountMinor > 0
                        ? '+${plain(line.amountMinor)}'
                        : '-${plain(-line.amountMinor)}',
                    style: AppTypography.rowAmount(
                      line.amountMinor < 0
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
