import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/contacts_repository.dart';
import '../../../data/repositories/documents_repository.dart';
import '../../../domain/documents/invoice.dart';
import '../../../domain/people/phone_number.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../theme/pesa_colors.dart';
import '../../currency/application/currency_controller.dart';
import '../../people/presentation/remind_sheet.dart';
import '../../reminders/application/business_reminders.dart';
import '../../security/application/balance_visibility.dart';
import '../application/invoice_providers.dart';
import '../application/invoice_sender.dart';

enum _Filter {
  all('All'),
  unpaid('Unpaid'),
  paid('Paid');

  const _Filter(this.label);

  final String label;
}

/// Invoices: what is waiting to be paid and overdue, then each invoice
/// with its status, which changes when a payment message matches.
class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen> {
  var _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final views = ref.watch(invoicesProvider).value;
    final hidden = ref.watch(balancesHiddenProvider);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    String plain(int minor) =>
        hidden ? maskedDigits : formatMoney(Money(minor), withCurrency: false);
    final open = [
      for (final v in views ?? const <InvoiceView>[])
        if (v.status != InvoiceStatus.paid) v,
    ];
    final waiting = open.fold(0, (sum, v) => sum + v.leftMinor);
    final overdue = open
        .where((v) => v.status == InvoiceStatus.overdue)
        .fold(0, (sum, v) => sum + v.leftMinor);
    final shown = [
      for (final v in views ?? const <InvoiceView>[])
        if (switch (_filter) {
          _Filter.all => true,
          _Filter.unpaid => v.status != InvoiceStatus.paid,
          _Filter.paid => v.status == InvoiceStatus.paid,
        })
          v,
    ];

    Widget tile(String label, String value, {Key? key}) => Expanded(
      child: Card(
        key: key,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              Text(value, style: theme.textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
          TextButton(
            key: const Key('invoices-new'),
            onPressed: () => context.push(AppRoutes.newInvoice()),
            child: Text('New', style: TextStyle(color: colors.link)),
          ),
        ],
      ),
      body: views == null
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Row(
                  children: [
                    tile(
                      'Waiting to be paid',
                      plain(waiting),
                      key: const Key('invoices-waiting'),
                    ),
                    const SizedBox(width: 10),
                    tile(
                      'Overdue',
                      plain(overdue),
                      key: const Key('invoices-overdue'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ChoiceMenu<_Filter>(
                    key: const Key('invoices-filter'),
                    name: 'Show',
                    options: [for (final f in _Filter.values) (f, f.label)],
                    value: _filter,
                    highlight: _filter != _Filter.all,
                    itemKey: (f) => Key('invoices-${f.name}'),
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                ),
                const SizedBox(height: 12),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'Invoices you make show here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  )
                else
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final (n, v) in shown.indexed) ...[
                          if (n > 0)
                            const Divider(height: 1, indent: 16, endIndent: 16),
                          _InvoiceRow(v, plain: plain, today: today),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Status changes on its own when a payment message matches.',
                  style: theme.textTheme.bodySmall!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  const _InvoiceRow(this.view, {required this.plain, required this.today});

  final InvoiceView view;
  final String Function(int) plain;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final i = view.invoice;
    final t = i.totals;
    final detail = switch (view.status) {
      InvoiceStatus.paid => [
        'Paid',
        if (t.withheldMinor > 0) 'tax withheld',
      ].join(' · '),
      InvoiceStatus.partPaid =>
        'Paid ${plain(view.paidMinor)} of ${plain(t.toPayMinor)}',
      InvoiceStatus.overdue => 'Was due ${shortDate(i.dueOn!)}',
      InvoiceStatus.unpaid =>
        i.dueOn == null ? 'Unpaid' : 'Due ${shortDate(i.dueOn!)}',
    };
    final (fg, bg) = switch (view.status) {
      InvoiceStatus.paid => (colors.successText, colors.success),
      InvoiceStatus.overdue => (theme.colorScheme.primary, colors.brandSoft),
      _ => (colors.warning, colors.warning),
    };
    return InkWell(
      key: Key('invoice-${i.number}'),
      onTap: () => showShareInvoiceSheet(context, view),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(i.client, style: theme.textTheme.titleMedium),
                  Text(
                    [
                      i.number,
                      detail,
                      if (view.attached > 0) '${view.attached} attached',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(plain(t.toPayMinor), style: theme.textTheme.titleMedium),
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: bg.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    view.status.label,
                    style: theme.textTheme.labelSmall!.copyWith(color: fg),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Save or share an invoice: one PDF or separate files, to the phone or
/// through any app.
Future<void> showShareInvoiceSheet(BuildContext context, InvoiceView view) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: _ShareInvoice(view),
          ),
        ),
      ),
    );

class _ShareInvoice extends ConsumerStatefulWidget {
  const _ShareInvoice(this.view);

  final InvoiceView view;

  @override
  ConsumerState<_ShareInvoice> createState() => _ShareInvoiceState();
}

class _ShareInvoiceState extends ConsumerState<_ShareInvoice> {
  final _number = TextEditingController();
  CallingCode? _code;
  List<String> _attachments = const [];
  var _one = true;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final contact = await ref
        .read(contactsRepositoryProvider)
        .byName(widget.view.invoice.client);
    final attached = await ref
        .read(documentsRepositoryProvider)
        .attachments(widget.view.invoice.id);
    if (!mounted) return;
    setState(() {
      _attachments = [for (final a in attached) a.name];
      _code = callingCodeFor(ref.read(deviceRegionProvider));
      final phone = contact?.phone;
      if (phone != null) {
        final match = callingCodes
            .where((c) => phone.startsWith('+${c.code}'))
            .firstOrNull;
        _code = match ?? _code;
        _number.text = match == null
            ? phone
            : phone.substring(match.code.length + 1);
      }
    });
  }

  Future<void> _pickContact() async {
    final picked = await ref.read(contactPickerProvider).pickPhone();
    if (picked == null || !mounted) return;
    final digits = picked.number.replaceAll(RegExp(r'[^\d+]'), '');
    final match = digits.startsWith('+')
        ? callingCodes.where((c) => digits.startsWith('+${c.code}')).firstOrNull
        : null;
    setState(() {
      if (match != null) _code = match;
      _number.text = match == null
          ? picked.number.trim()
          : digits.substring(match.code.length + 1);
    });
  }

  Future<void> _go({required bool save}) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      if (_number.text.trim().isNotEmpty) {
        final existing = await ref
            .read(contactsRepositoryProvider)
            .byName(widget.view.invoice.client);
        await ref
            .read(contactsRepositoryProvider)
            .save(
              Contact(
                name: widget.view.invoice.client,
                phone: internationalNumber(
                  _number.text,
                  _code ?? callingCodes.first,
                ),
                sendWith: existing?.sendWith,
              ),
            );
      }
      final sender = ref.read(invoiceSenderProvider);
      final doc = await sender.docFor(widget.view);
      if (save) {
        final saved = await sender.save(doc, one: _one);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              saved == 0
                  ? 'Nothing was saved.'
                  : saved == 1
                  ? 'Saved to your phone.'
                  : '$saved files saved to your phone.',
            ),
          ),
        );
      } else {
        await sender.share(doc, one: _one);
      }
      navigator.pop();
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('The invoice was not made. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final i = widget.view.invoice;
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    String plain(int minor) => formatMoney(Money(minor), withCurrency: false);
    final parts = [
      ('Invoice', widget.view.status == InvoiceStatus.paid ? 'Paid' : 'PDF'),
      if (i.timesheet) ('Timesheet', 'PDF'),
      for (final a in _attachments)
        (a.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), ''), 'attached'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Invoice ${i.number}', style: theme.textTheme.headlineSmall),
        Text(
          [
            i.client,
            '${i.currency} ${plain(i.totals.toPayMinor)}',
            if (i.dueOn case final due?) 'due ${shortDate(due)}',
          ].join(' · '),
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 12),
        Wrap(
          runSpacing: 8,
          children: [
            for (final (name, kind) in parts)
              Container(
                width: 76,
                height: 92,
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.all(8),
                alignment: Alignment.bottomLeft,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium,
                    ),
                    Text(kind, style: muted),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Send as',
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              key: const Key('invoice-one-pdf'),
              label: const Text('One PDF'),
              selected: _one,
              onSelected: (_) => setState(() => _one = true),
            ),
            ChoiceChip(
              key: const Key('invoice-separate'),
              label: const Text('Separate files'),
              selected: !_one,
              onSelected: (_) => setState(() => _one = false),
            ),
          ],
        ),
        const SizedBox(height: 12),
        PhoneField(
          code: _code ?? callingCodes.first,
          controller: _number,
          label: 'Send to (optional)',
          onCode: (c) => setState(() => _code = c),
          onPick: _pickContact,
        ),
        const SizedBox(height: 4),
        Text(
          "From the client's details, or choose from your contacts.",
          style: muted,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('invoice-save-phone'),
                onPressed: _busy ? null : () => _go(save: true),
                child: const Text('Save to phone'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                key: const Key('invoice-share'),
                onPressed: _busy ? null : () => _go(save: false),
                child: const Text('Share'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Made on this phone. Saved to Files or Downloads, or shared through '
          'any app.',
          textAlign: TextAlign.center,
          style: muted,
        ),
      ],
    );
  }
}
