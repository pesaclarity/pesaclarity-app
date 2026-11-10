import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart' hide Tag;
import '../../../domain/ledger/activity_lines.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/format/ledger_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../../payees/presentation/transaction_sheet.dart';
import '../application/cash_book_providers.dart';

/// Money tab: the business's cash book. What Cash, M-Pesa and Bank hold,
/// then each day's money in and out.
class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({super.key});

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends ConsumerState<MoneyScreen> {
  var _pages = 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final from = today.addDays(1 - cashBookPageDays * _pages);
    final loaded = ref.watch(cashBookProvider(from));
    final book = loaded.value;
    final accounts = ref.watch(activityAccountsProvider).value ?? const {};
    final categories = ref.watch(activityCategoriesProvider).value ?? const {};
    final hidden = AmountsHidden.of(context);

    String plain(int minor) =>
        moneyOrHidden(minor, hidden: hidden, withCurrency: false);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            TabHeader(
              'Money',
              semanticsId: SemanticIds.titleMoney,
              actions: [
                TextButton(
                  key: const Key('money-close-day'),
                  onPressed: () => context.push(AppRoutes.closeDay),
                  child: const Text('Close the day'),
                ),
                IconButton(
                  key: const Key('money-search'),
                  tooltip: 'Search all records',
                  icon: const Icon(Icons.search),
                  onPressed: () => context.go(AppRoutes.activity),
                ),
                const AmountsEye(),
              ],
            ),
            if (book == null && loaded.hasError)
              ErrorView(
                'Money in and out could not load.',
                onRetry: () => ref.invalidate(cashBookProvider(from)),
              )
            else if (book == null)
              const LoadingView(inList: true)
            else ...[
              if (book.balances.isNotEmpty)
                FigureRow(
                  children: [
                    for (final MapEntry(:key, :value) in book.balances.entries)
                      FigureTile(
                        key: Key('money-balance-${key.name}'),
                        label: key.label,
                        value: plain(value),
                      ),
                  ],
                ),
              if (book.days.isEmpty)
                const EmptyNote(
                  'Sales and costs show here once your messages are read, '
                  'or when you add one with +.',
                )
              else
                for (final day in book.days) ...[
                  SectionLabel(
                    dayHeading(day.date, today: today),
                    trailing: Text(
                      'In ${plain(day.inMinor)} · '
                      'Out ${plain(day.outMinor)}',
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, line) in day.lines.indexed) ...[
                          if (i > 0) const Divider(height: 1),
                          CashBookRow(
                            line: line,
                            accounts: accounts,
                            categories: categories,
                            plain: plain,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _pages++),
                  child: const Text('Show older'),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('money-sell'),
        tooltip: 'Sell',
        shape: const CircleBorder(),
        onPressed: () => context.push(AppRoutes.sell),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// One cash book line: what it was, the account it moved through and when,
/// and the amount in or out.
class CashBookRow extends StatelessWidget {
  const CashBookRow({
    required this.line,
    required this.accounts,
    required this.categories,
    required this.plain,
    super.key,
  });

  final ActivityLine line;
  final Map<int, Account> accounts;
  final Map<int, Category> categories;
  final String Function(int minor) plain;

  String _account(int id) => accounts[id]?.name ?? 'Account';

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    return switch (line) {
      EntryLine(:final entry) => _row(
        context,
        title: cashBookTitle(
          entry,
          categoryName: categories[entry.categoryId]?.name,
        ),
        account: _account(entry.accountId),
        when: formatTime(entry.occurredAt),
        amount: _signed(context, entry.signedMinor),
        onTap: () => showTransactionSheet(context, entry.id),
      ),
      OwnTransferLine(:final outflow, :final inflow, :final shown) => _row(
        context,
        title: outflow != null
            ? 'Moved to ${inflow == null ? 'another account' : _account(inflow.accountId)}'
            : 'Moved from another account',
        account: _account(shown.accountId),
        when: formatTime(shown.occurredAt),
        amount: Text(
          plain(shown.amountMinor),
          style: AppTypography.rowAmount(colors.textMuted),
        ),
      ),
      DailyNoiseLine() && final noise => _row(
        context,
        title: noiseTitle(noise.group),
        account: _account(noise.accountId),
        when: noise.count == 1 ? '1 entry' : '${noise.count} entries',
        amount: _signed(
          context,
          noise.direction == TransactionDirection.inflow
              ? noise.totalMinor
              : -noise.totalMinor,
        ),
      ),
    };
  }

  Widget _row(
    BuildContext context, {
    required String title,
    required String account,
    required String when,
    required Widget amount,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(child: Tag(account)),
                      const SizedBox(width: 8),
                      Text(
                        when,
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            amount,
          ],
        ),
      ),
    );
  }

  Widget _signed(BuildContext context, int signedMinor) {
    final colors = PesaColors.of(context);
    final inflow = signedMinor > 0;
    return Text(
      inflow ? '+${plain(signedMinor)}' : '-${plain(-signedMinor)}',
      style: AppTypography.rowAmount(
        inflow ? colors.successText : Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}
