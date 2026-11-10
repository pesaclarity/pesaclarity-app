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
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../../currency/application/currency_controller.dart';
import '../../people/presentation/remind_sheet.dart';
import '../../printing/presentation/print_sheet.dart';
import '../../reminders/application/business_reminders.dart';
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
    final loaded = ref.watch(invoicesProvider);
    final views = loaded.value;
    final hidden = AmountsHidden.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    String plain(int minor) =>
        moneyOrHidden(minor, hidden: hidden, withCurrency: false);
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
          TextButton(
            key: const Key('invoices-new'),
            onPressed: () => context.push(AppRoutes.newInvoice()),
            child: const Text('New invoice'),
          ),
          const AmountsEye(),
          const SizedBox(width: 8),
        ],
      ),
      body: views == null
          ? loaded.hasError
                ? ErrorView(
                    'Your invoices could not load.',
                    onRetry: () => ref.invalidate(invoicesProvider),
                  )
                : const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                FigureRow(
                  children: [
                    FigureTile(
                      key: const Key('invoices-waiting'),
                      label: 'Waiting to be paid',
                      value: plain(waiting),
                    ),
                    FigureTile(
                      key: const Key('invoices-overdue'),
                      label: 'Overdue',
                      value: plain(overdue),
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
                  const EmptyNote('Invoices you make show here.')
                else
                  GroupedSection(
                    children: [
                      for (final v in shown)
                        _InvoiceRow(v, plain: plain, today: today),
                    ],
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
    final tone = switch (view.status) {
      InvoiceStatus.paid => Tone.success,
      InvoiceStatus.overdue => Tone.warning,
      _ => Tone.info,
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
                Text(
                  plain(t.toPayMinor),
                  style: AppTypography.rowAmount(theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 2),
                Tag(view.status.label, tone: tone),
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
    showAppSheet<void>(context: context, builder: (_) => _ShareInvoice(view));

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
        if (mounted) {
          showNote(
            context,
            saved == 0
                ? 'The invoice was not saved. Try again.'
                : saved == 1
                ? 'Saved to your phone.'
                : '$saved files saved to your phone.',
          );
        }
      } else {
        await sender.share(doc, one: _one);
      }
      navigator.pop();
    } on Object {
      if (mounted) showNote(context, 'The invoice was not made. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final sender = ref.read(invoiceSenderProvider);
    final doc = await sender.docFor(widget.view);
    if (!mounted) return;
    final i = widget.view.invoice;
    await showPrintSheet(
      context,
      title: 'Print invoice',
      subtitle: [i.number, if (i.client.isNotEmpty) i.client].join(' · '),
      name: 'Invoice ${i.number}',
      pdf: () => sender.pdf(doc),
      fullPage: true,
    );
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

    return SheetBody(
      title: 'Invoice ${i.number}',
      subtitle: [
        i.client,
        '${i.currency} ${plain(i.totals.toPayMinor)}',
        if (i.dueOn case final due?) 'due ${shortDate(due)}',
      ].join(' · '),
      children: [
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
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AdaptiveSegmented<bool>(
            key: const Key('invoice-send-as'),
            name: 'Send as',
            segments: const [(true, 'One PDF'), (false, 'Separate files')],
            selected: _one,
            onChanged: (one) => setState(() => _one = one),
          ),
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
        ButtonPair(
          primary: FilledButton(
            key: const Key('invoice-share'),
            onPressed: _busy ? null : () => _go(save: false),
            child: const Text('Share'),
          ),
          secondary: OutlinedButton(
            key: const Key('invoice-save-phone'),
            onPressed: _busy ? null : () => _go(save: true),
            child: const Text('Save to phone'),
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('invoice-print'),
          onPressed: _busy ? null : _print,
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print'),
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
