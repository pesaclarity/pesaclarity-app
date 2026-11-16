import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/balances_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/ledger/activity_lines.dart';
import '../../../domain/ledger/own_transfers.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../application/balances_providers.dart';
import 'balance_text.dart';
import 'balances_screen.dart';

/// "KCB → M-Pesa", for an own transfer's line.
String transferTitle(OwnTransferLine line, Map<int, Account> accounts) {
  String name(int? id) => accounts[id]?.name ?? 'Account';
  final out = line.outflow;
  final into = line.inflow;
  if (out != null && into != null) {
    return '${name(out.accountId)} → ${name(into.accountId)}';
  }
  final shown = line.shown;
  final other = shown.transferAccountId;
  if (other != null) {
    return shown.isOutflow
        ? '${name(shown.accountId)} → ${name(other)}'
        : '${name(other)} → ${name(shown.accountId)}';
  }
  return out != null
      ? 'From ${name(out.accountId)}'
      : 'To ${name(into!.accountId)}';
}

/// "Own transfer · not spending · fee 30", or what it waits for.
String transferSubtitle(
  BuildContext context,
  OwnTransferLine line,
  Map<int, Account> accounts,
) {
  final shown = line.shown;
  final other = shown.transferAccountId;
  if (shown.transferPairId == null && other != null) {
    return BalanceText.waitingFor(accounts[other]?.name ?? 'Account');
  }
  final fee = line.outflow?.feeMinor ?? 0;
  return [
    BalanceText.ownTransfer,
    BalanceText.notSpending,
    if (fee > 0) BalanceText.feeOf(shownMoney(context, fee)),
  ].join(' · ');
}

/// A matched own transfer: both sides, and Unmatch.
Future<void> showOwnTransferSheet(BuildContext context, OwnTransferLine line) =>
    showAppSheet<void>(
      context: context,
      builder: (context) => AmountsHiddenScope(child: _OwnTransferSheet(line)),
    );

class _OwnTransferSheet extends ConsumerWidget {
  const _OwnTransferSheet(this.line);

  final OwnTransferLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(activityAccountsProvider).value ?? const {};
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final shown = line.shown;
    String when(DateTime at) =>
        '${dayHeading(CalendarDate.local(at), today: today)} ${formatTime(at)}';
    return SheetBody(
      title: transferTitle(line, accounts),
      subtitle: transferSubtitle(context, line, accounts),
      children: [
        Card(
          child: Column(
            children: [
              if (line.outflow case final out?)
                LabelValueRow(
                  label: 'Out of ${accounts[out.accountId]?.name ?? ''}',
                  detail: when(out.occurredAt),
                  value: shownMoney(context, out.amountMinor),
                ),
              if (line.inflow case final into?)
                LabelValueRow(
                  label: 'Into ${accounts[into.accountId]?.name ?? ''}',
                  detail: when(into.occurredAt),
                  value: shownMoney(context, into.amountMinor),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          BalanceText.unmatchNote,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          key: const Key('own-transfer-unmatch'),
          onPressed: () async {
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            final transactions = ref.read(transactionsRepositoryProvider);
            if (shown.transferPairId != null) {
              await transactions.unmatch(shown.id);
            } else {
              await transactions.setTransferAccount(shown.id, null);
            }
            navigator.pop();
            messenger.showSnackBar(
              const SnackBar(content: Text(BalanceText.unmatched)),
            );
          },
          child: const Text(BalanceText.unmatch),
        ),
      ],
    );
  }
}

/// On a transaction's sheet: for money in or out not yet matched, "Was
/// this your own money?" with the likely other side, or choosing the other
/// account so its side can come later. For a balance correction, Undo.
class OwnMoneySection extends ConsumerWidget {
  const OwnMoneySection(this.record, {super.key});

  final TransactionRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    if (record.kind == TransactionKind.correction) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OutlinedButton(
          key: const Key('transaction-undo-correction'),
          onPressed: () async {
            final navigator = Navigator.of(context);
            await ref
                .read(balancesRepositoryProvider)
                .undoCorrection(record.id);
            navigator.pop();
          },
          child: const Text('Undo this correction'),
        ),
      );
    }
    if (record.transferPairId != null || record.transferAccountId != null) {
      return const SizedBox.shrink();
    }
    final accounts = ref.watch(activityAccountsProvider).value ?? const {};
    final others = [
      for (final a in accounts.values)
        if (a.id != record.accountId) a,
    ];
    if (others.isEmpty) return const SizedBox.shrink();
    final suggestions =
        ref
            .watch(
              transferSuggestionsProvider((
                id: record.id,
                at: record.occurredAt,
              )),
            )
            .value ??
        const [];
    final isIn = record.direction == TransactionDirection.inflow;
    final today = CalendarDate.local(ref.watch(clockProvider)());

    Future<void> match(TransferSuggestion s) async {
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      await ref
          .read(transactionsRepositoryProvider)
          .match(
            isIn ? s.partner.id : record.id,
            isIn ? record.id : s.partner.id,
          );
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text(BalanceText.matched)),
      );
    }

    Future<void> chooseAccount() async {
      final chosen = await showAppSheet<int>(
        context: context,
        builder: (context) => SheetBody(
          title: isIn ? BalanceText.fromAnother : BalanceText.toAnother,
          children: [
            for (final a in others)
              ListTile(
                key: Key('own-account-${a.id}'),
                contentPadding: EdgeInsets.zero,
                leading: AccountLetter(a.name),
                title: Text(a.name),
                onTap: () => Navigator.pop(context, a.id),
              ),
          ],
        ),
      );
      if (chosen == null || !context.mounted) return;
      final navigator = Navigator.of(context);
      await ref
          .read(transactionsRepositoryProvider)
          .setTransferAccount(record.id, chosen);
      navigator.pop();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            BalanceText.ownMoney.toUpperCase(),
            style: theme.textTheme.labelMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Card(
            child: Column(
              children: [
                for (final s in suggestions)
                  ListTile(
                    key: Key('own-suggestion-${s.partner.id}'),
                    leading: AccountLetter(
                      accounts[s.partner.accountId]?.name ?? '#',
                    ),
                    title: Text(
                      '${accounts[s.partner.accountId]?.name ?? 'Account'}, '
                      '${shownMoney(context, s.partner.amountMinor, withCurrency: true)} '
                      '${s.partner.isOutflow ? 'out' : 'in'}',
                    ),
                    subtitle: Text(
                      [
                        '${dayHeading(s.partner.date, today: today)} '
                            '${formatTime(s.partner.occurredAt)}',
                        if (s.feeMinor(record.amountMinor) > 0)
                          BalanceText.plusFee(
                            shownMoney(
                              context,
                              isIn ? record.amountMinor : s.partner.amountMinor,
                            ),
                            shownMoney(context, s.feeMinor(record.amountMinor)),
                          ),
                      ].join(' · '),
                    ),
                    trailing: TextButton(
                      key: Key('own-match-${s.partner.id}'),
                      onPressed: () => match(s),
                      child: const Text(BalanceText.match),
                    ),
                  ),
                ListTile(
                  key: const Key('own-choose-account'),
                  leading: const IconBadge(Icons.add),
                  title: Text(
                    isIn ? BalanceText.fromAnother : BalanceText.toAnother,
                  ),
                  subtitle: const Text(BalanceText.itsSideLater),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: chooseAccount,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
