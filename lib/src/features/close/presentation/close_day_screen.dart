import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/day_closes_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/close/day_close.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/people/people.dart';
import '../../../domain/printing/slip.dart';
import '../../../domain/printing/slips.dart';
import '../../../domain/sales/sales_summary.dart';
import '../../../domain/time/business_day.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../../documents/application/document_providers.dart';
import '../../people/application/people_providers.dart';
import '../../printing/application/printing_providers.dart';
import '../../printing/presentation/print_sheet.dart';
import '../../sales/application/sales_providers.dart';
import '../../sales/presentation/pay_sheet.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/business_day_providers.dart';

/// Today's drawer: what it should hold from the records.
final todayCashProvider = FutureProvider<DayCash>((ref) async {
  ref.watch(ledgerChangesProvider);
  final business = await ref.watch(businessDayProvider.future);
  final today = business.dayOf(ref.watch(clockProvider)());
  final cash = [
    for (final a in await ref.watch(accountsRepositoryProvider).openings())
      if (a.type == AccountType.cash) a,
  ];
  final entries = await ref
      .watch(transactionsRepositoryProvider)
      .ledgerEntries(from: DateTime.utc(1970), to: business.endOf(today));
  return dayCash(cash, entries, day: today, business: business);
});

/// Money in today with no record yet.
final unmatchedTodayProvider = FutureProvider<List<LedgerEntry>>((ref) async {
  ref.watch(ledgerChangesProvider);
  final business = await ref.watch(businessDayProvider.future);
  final today = business.dayOf(ref.watch(clockProvider)());
  return ref
      .watch(salesControllerProvider)
      .unmatchedOn(today, business: business);
});

/// What happens to a difference between the drawer and the records.
enum _Difference { note, book }

/// Close the day: what the drawer should hold against what was counted,
/// money in still to match, and today's sales. It never books a difference
/// on its own.
class CloseDayScreen extends ConsumerStatefulWidget {
  const CloseDayScreen({super.key});

  @override
  ConsumerState<CloseDayScreen> createState() => _CloseDayScreenState();
}

class _CloseDayScreenState extends ConsumerState<CloseDayScreen> {
  final _counted = TextEditingController();
  final _note = TextEditingController();
  var _difference = _Difference.note;
  var _saving = false;

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

  Future<void> _close(DayCash cash) async {
    final counted = AmountField.amountFrom(_counted.text);
    if (counted == null) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final now = ref.read(clockProvider)();
      final business = await ref.read(businessDayProvider.future);
      final gap = counted - cash.expectedMinor;
      if (gap != 0 && _difference == _Difference.book) {
        await ref.read(salesControllerProvider).bookCashDifference(gap);
      }
      final note = _note.text.trim();
      await ref
          .read(dayClosesRepositoryProvider)
          .save(
            DayClose(
              day: business.dayOf(now),
              expectedMinor: cash.expectedMinor,
              countedMinor: counted,
              note: note.isEmpty ? null : note,
            ),
            at: now,
          );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            gap == 0 ? 'Day closed. The drawer matches.' : 'Day closed.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _match(LedgerEntry e) async {
    final controller = ref.read(salesControllerProvider);
    final customers = [
      for (final c
          in ref.read(customersProvider).value ?? const <CustomerAccount>[])
        if (c.owedMinor > 0) c,
    ];
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('match-sale'),
              leading: const Icon(Icons.point_of_sale),
              title: const Text('A sale'),
              onTap: () => Navigator.pop(context, 'sale'),
            ),
            for (final c in customers)
              ListTile(
                key: Key('match-customer-${c.name}'),
                leading: const Icon(Icons.person_outline),
                title: Text('${c.name} paying what they owe'),
                subtitle: Text('Owes ${_plain(c.owedMinor)}'),
                onTap: () => Navigator.pop(context, c),
              ),
            ListTile(
              key: const Key('match-other'),
              leading: const Icon(Icons.savings_outlined),
              title: const Text('Other income'),
              onTap: () => Navigator.pop(context, 'other'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    switch (choice) {
      case 'sale':
        await controller.saleFromPayment(e);
      case 'other':
        await controller.otherIncome(e);
      case CustomerAccount(:final name):
        await controller.customerPaidBy(e, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final business =
        ref.watch(businessDayProvider).value ?? BusinessDay.midnight;
    final today = business.dayOf(ref.watch(clockProvider)());
    final cash = ref.watch(todayCashProvider).value;
    final unmatched = ref.watch(unmatchedTodayProvider).value ?? const [];
    final accounts = ref.watch(activityAccountsProvider).value ?? const {};
    final sales = ref.watch(salesTodayProvider).value?.day;

    return Scaffold(
      appBar: AppBar(title: const Text('Close the day')),
      body: cash == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  business.endsAtHour == 0
                      ? longDate(today)
                      : '${longDate(today)} · business day until '
                            '${business.endLabel}',
                  key: const Key('close-day-date'),
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Should be in the drawer'),
                        subtitle: Text(
                          'Start ${_plain(cash.startMinor)} + in '
                          '${_plain(cash.inMinor)} − out '
                          '${_plain(cash.outMinor)}',
                        ),
                        trailing: Text(
                          _plain(cash.expectedMinor),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: AmountField(
                          key: const Key('close-counted'),
                          controller: _counted,
                          label: 'Cash you counted',
                          allowZero: true,
                        ),
                      ),
                    ],
                  ),
                ),
                ListenableBuilder(
                  listenable: _counted,
                  builder: (context, _) {
                    final counted = AmountField.amountFrom(_counted.text);
                    if (counted == null || _counted.text.trim().isEmpty) {
                      return const SizedBox.shrink();
                    }
                    final gap = counted - cash.expectedMinor;
                    if (gap == 0) {
                      return const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: InfoNote('The drawer matches the records.'),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          InfoNote(
                            key: const Key('close-gap'),
                            '${_plain(gap.abs())} ${gap > 0 ? 'more' : 'less'} '
                            'than the records. Add a missed sale or cost '
                            'with + if you know it, or keep it below.',
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                key: const Key('close-note'),
                                label: const Text('Keep a note'),
                                selected: _difference == _Difference.note,
                                onSelected: (_) => setState(
                                  () => _difference = _Difference.note,
                                ),
                              ),
                              ChoiceChip(
                                key: const Key('close-book'),
                                label: const Text('Book a cash difference'),
                                selected: _difference == _Difference.book,
                                onSelected: (_) => setState(
                                  () => _difference = _Difference.book,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('close-note-text'),
                            controller: _note,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Note (optional)',
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                if (unmatched.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
                    child: Text(
                      'PAYMENTS NOT MATCHED TO A SALE',
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
                        for (final (i, e) in unmatched.indexed) ...[
                          if (i > 0)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            key: Key('unmatched-${e.id}'),
                            title: Text(
                              e.payeeName ?? e.counterpartyName ?? 'Payment',
                            ),
                            subtitle: Text(
                              '${accounts[e.accountId]?.name ?? 'Account'} · '
                              '${formatTime(e.occurredAt)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _plain(e.amountMinor),
                                  style: theme.textTheme.titleMedium,
                                ),
                                TextButton(
                                  onPressed: () => _match(e),
                                  child: Text(
                                    'Match',
                                    style: TextStyle(color: colors.link),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Match a payment to a sale, a customer who owes you, or '
                    'keep it as other income.',
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
                if (sales != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    margin: EdgeInsets.zero,
                    child: ListTile(
                      title: const Text('Total sales today'),
                      subtitle: sales.byWay.isEmpty
                          ? null
                          : Text(
                              [
                                for (final MapEntry(:key, :value)
                                    in sales.byWay.entries)
                                  '${methodLabel(key)} ${_plain(value)}',
                              ].join(' · '),
                            ),
                      trailing: Text(
                        _plain(sales.totalMinor),
                        style: theme.textTheme.titleMedium!.copyWith(
                          color: colors.successText,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ListenableBuilder(
                  listenable: _counted,
                  builder: (context, _) => FilledButton(
                    key: const Key('close-day'),
                    onPressed:
                        _saving ||
                            _counted.text.trim().isEmpty ||
                            AmountField.amountFrom(_counted.text) == null
                        ? null
                        : () => _close(cash),
                    child: const Text('Close the day'),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('close-print'),
                  onPressed: () => _print(cash, sales),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text("Print the day's summary"),
                ),
              ],
            ),
    );
  }

  Future<void> _print(DayCash cash, SalesDay? sales) async {
    final settings = await ref.read(documentSettingsProvider.future);
    if (!mounted) return;
    final business = await ref.read(businessDayProvider.future);
    if (!mounted) return;
    final now = ref.read(clockProvider)();
    final today = business.dayOf(now);
    final counted = _counted.text.trim().isEmpty
        ? null
        : AmountField.amountFrom(_counted.text);
    Slip slip() => daySummarySlip(
      business: settings.nameOr(ref.read(activeSpaceProvider).name),
      date: longDate(today),
      salesMinor: sales?.totalMinor ?? 0,
      salesByWay: sales?.byWay ?? const {},
      startMinor: cash.startMinor,
      inMinor: cash.inMinor,
      outMinor: cash.outMinor,
      expectedMinor: cash.expectedMinor,
      countedMinor: counted,
      printedAt: formatTime(now),
      label: methodLabel,
      plain: _plain,
    );
    await showPrintSheet(
      context,
      title: "Print the day's summary",
      subtitle: longDate(today),
      name: 'Day summary $today',
      slip: slip,
      pdf: () => slipPdf(slip()),
    );
  }
}
