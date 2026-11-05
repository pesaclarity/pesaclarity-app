import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/sales/sale_matching.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../application/sales_providers.dart';
import 'pay_sheet.dart';
import 'records_sheets.dart';

/// Payment messages near a waiting sale part, to choose from.
final _candidatesProvider =
    FutureProvider.family<List<LedgerEntry>, WaitingPayment>(
      (ref, w) => ref.watch(salesControllerProvider).candidatesFor(w),
    );

/// Choose payments: the messages that paid a sale, and what happened to any
/// difference. Returns true once saved.
Future<bool?> showChoosePaymentsSheet(
  BuildContext context,
  WaitingPayment waiting,
) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: _ChoosePayments(waiting),
      ),
    ),
  ),
);

class _ChoosePayments extends ConsumerStatefulWidget {
  const _ChoosePayments(this.waiting);

  final WaitingPayment waiting;

  @override
  ConsumerState<_ChoosePayments> createState() => _ChoosePaymentsState();
}

class _ChoosePaymentsState extends ConsumerState<_ChoosePayments> {
  final _picked = <int>{};
  ShortBy _short = ShortBy.theyOweIt;
  OverBy _over = OverBy.changeInCash;
  final _customer = TextEditingController();
  CalendarDate? _due;
  var _saving = false;

  @override
  void dispose() {
    _customer.dispose();
    super.dispose();
  }

  String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

  Future<void> _save(List<LedgerEntry> chosen) async {
    final paid = chosen.fold(0, (sum, e) => sum + e.amountMinor);
    final short = paid < widget.waiting.amountMinor;
    final customer = _customer.text.trim();
    if (short && _short == ShortBy.theyOweIt && customer.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter who owes the rest.')));
      return;
    }
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(salesControllerProvider)
          .settle(
            widget.waiting,
            chosen,
            short: short ? _short : null,
            over: paid > widget.waiting.amountMinor ? _over : null,
            credit: short && _short == ShortBy.theyOweIt
                ? CreditTerms(customer: customer, dueDate: _due)
                : null,
          );
      navigator.pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final w = widget.waiting;
    final candidates = ref.watch(_candidatesProvider(w)).value;
    final accounts = ref.watch(activityAccountsProvider).value ?? const {};
    final chosen = [
      for (final e in candidates ?? const <LedgerEntry>[])
        if (_picked.contains(e.id)) e,
    ];
    final paid = chosen.fold(0, (sum, e) => sum + e.amountMinor);
    final gap = w.amountMinor - paid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Choose payments', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Pick the payments for this sale of '
          '${formatMoney(Money(w.amountMinor))}.',
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 12),
        if (candidates == null)
          const Center(child: CircularProgressIndicator.adaptive())
        else if (candidates.isEmpty)
          Text(
            'Payments that come in around the time of the sale show here.',
            style: theme.textTheme.bodyMedium,
          )
        else
          for (final e in candidates)
            CheckboxListTile(
              key: Key('choose-${e.id}'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _picked.contains(e.id),
              onChanged: (on) => setState(() {
                on == true ? _picked.add(e.id) : _picked.remove(e.id);
                if (_customer.text.isEmpty) {
                  _customer.text = e.payeeName ?? e.counterpartyName ?? '';
                }
              }),
              title: Text(
                '${e.payeeName ?? e.counterpartyName ?? 'Payment'} · '
                '${_plain(e.amountMinor)}',
              ),
              subtitle: Text(
                '${accounts[e.accountId]?.name ?? 'Account'} · '
                '${formatTime(e.occurredAt)}',
              ),
            ),
        if (chosen.isNotEmpty) ...[
          const SizedBox(height: 8),
          InfoNote(
            gap == 0
                ? '${[for (final e in chosen) _plain(e.amountMinor)].join(' + ')}'
                      ' = ${_plain(paid)}. That covers this sale.'
                : gap > 0
                ? 'That is ${_plain(gap)} less than the sale.'
                : 'That is ${_plain(-gap)} more than the sale.',
            key: const Key('choose-total'),
          ),
          if (gap > 0) ...[
            const SizedBox(height: 12),
            Text(
              'What about the ${_plain(gap)}?',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (choice, label) in [
                  (ShortBy.theyOweIt, 'They owe it'),
                  (ShortBy.restInCash, 'Paid the rest in cash'),
                  (ShortBy.anotherPayment, 'Another payment'),
                  (ShortBy.discount, 'Gave a discount'),
                ])
                  ChoiceChip(
                    key: Key('short-${choice.name}'),
                    label: Text(label),
                    selected: _short == choice,
                    onSelected: (_) => setState(() => _short = choice),
                  ),
              ],
            ),
            if (_short == ShortBy.theyOweIt) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('choose-customer'),
                controller: _customer,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Who owes it'),
              ),
              const SizedBox(height: 12),
              DueDateChips(
                today: today,
                value: _due,
                onChanged: (d) => setState(() => _due = d),
              ),
            ],
          ],
          if (gap < 0) ...[
            const SizedBox(height: 12),
            Text(
              'What happened to the ${_plain(-gap)}?',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (choice, label) in [
                  (OverBy.changeInCash, 'Gave change in cash'),
                  (OverBy.changeByMpesa, 'Gave change by M-Pesa'),
                  (OverBy.keepWithSale, 'Keep it with the sale'),
                ])
                  ChoiceChip(
                    key: Key('over-${choice.name}'),
                    label: Text(label),
                    selected: _over == choice,
                    onSelected: (_) => setState(() => _over = choice),
                  ),
              ],
            ),
          ],
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('choose-save'),
          onPressed: chosen.isEmpty || _saving ? null : () => _save(chosen),
          child: Text(
            chosen.length == 1
                ? 'Use this payment'
                : 'Use these ${chosen.length} payments',
          ),
        ),
      ],
    );
  }
}
