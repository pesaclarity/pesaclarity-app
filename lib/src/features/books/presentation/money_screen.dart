import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/ledger/activity_lines.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/format/ledger_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../../activity/presentation/add_transaction_sheet.dart';
import '../../payees/presentation/transaction_sheet.dart';
import '../../security/application/balance_visibility.dart';
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
    final hidden = ref.watch(balancesHiddenProvider);

    String plain(int minor) =>
        hidden ? maskedDigits : formatMoney(Money(minor), withCurrency: false);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    identifier: SemanticIds.titleMoney,
                    child: Text(
                      'Money in and out',
                      style: theme.textTheme.headlineLarge,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('money-search'),
                  tooltip: 'Search all records',
                  icon: const Icon(Icons.search),
                  onPressed: () => context.go(AppRoutes.activity),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (book == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else ...[
              if (book.balances.isNotEmpty)
                Row(
                  children: [
                    for (final (i, MapEntry(:key, :value))
                        in book.balances.entries.indexed) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(
                        child: _BalanceChip(
                          key: Key('money-balance-${key.name}'),
                          label: key.label,
                          value: plain(value),
                        ),
                      ),
                    ],
                  ],
                ),
              if (book.days.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Text(
                    'Sales and costs show here once your messages are read, '
                    'or when you add one with +.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                )
              else
                for (final day in book.days) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            dayHeading(day.date, today: today).toUpperCase(),
                            style: theme.textTheme.labelLarge!.copyWith(
                              color: colors.textMuted,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        Text(
                          'In ${plain(day.inMinor)} · '
                          'Out ${plain(day.outMinor)}',
                          style: theme.textTheme.bodyMedium!.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (i, line) in day.lines.indexed) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                          _CashBookRow(
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
                  child: Text(
                    'Show older',
                    style: TextStyle(color: colors.link),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add a record',
        shape: const CircleBorder(),
        onPressed: () => showAddTransactionSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  const _BalanceChip({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: AppTypography.amount(
                  size: 20,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One cash book line: what it was, the account it moved through and when,
/// and the amount in or out.
class _CashBookRow extends StatelessWidget {
  const _CashBookRow({
    required this.line,
    required this.accounts,
    required this.categories,
    required this.plain,
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
          style: AppTypography.amount(size: 18, color: colors.textMuted),
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
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.border,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            account,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium!.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      ),
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
      style: AppTypography.amount(
        size: 18,
        color: inflow
            ? colors.successText
            : Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

/// A cash book line's title: what it was for, then who with, such as
/// `Sale · Grace W.`; without a category, who with or what kind it was.
String cashBookTitle(LedgerEntry entry, {String? categoryName}) {
  final party = entry.payeeName ?? entry.counterpartyName ?? entry.note;
  final parts = [?categoryName, ?party];
  if (parts.isNotEmpty) return parts.join(' · ');
  return entry.counterpartyValue ?? kindLabel(entry.kind);
}
