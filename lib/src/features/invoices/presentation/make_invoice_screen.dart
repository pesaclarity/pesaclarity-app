import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/hours_repository.dart';
import '../../../data/repositories/invoices_repository.dart';
import '../../../domain/documents/invoice.dart';
import '../../../domain/hours/hours.dart';
import '../../../domain/tax/tax_pack.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../documents/application/document_providers.dart';
import '../../hours/application/hours_providers.dart';
import '../../sales/presentation/records_sheets.dart';
import '../../tax/application/tax_providers.dart';
import '../application/invoice_providers.dart';
import 'attach_sheet.dart';
import 'invoices_screen.dart';

/// A line typed in: an item billed, or a cost passed on.
class _Typed {
  _Typed();

  final name = TextEditingController();
  final amount = TextEditingController();
  final quantity = TextEditingController(text: '1');

  void dispose() {
    name.dispose();
    amount.dispose();
    quantity.dispose();
  }
}

/// New invoice: the client, hours not billed yet or items, how the hours
/// show, costs passed on, withholding tax, and what the client pays.
class MakeInvoiceScreen extends ConsumerStatefulWidget {
  const MakeInvoiceScreen({this.client, super.key});

  final String? client;

  @override
  ConsumerState<MakeInvoiceScreen> createState() => _MakeInvoiceScreenState();
}

class _MakeInvoiceScreenState extends ConsumerState<MakeInvoiceScreen> {
  late final _client = TextEditingController(text: widget.client);
  final _notes = TextEditingController();
  var _billBy = BillBy.hours;
  CalendarDate? _from;
  late CalendarDate _to = _today;
  List<HourEntry> _unbilled = const [];
  final _projects = <String?>{};
  var _detail = HoursDetail.total;
  var _timesheet = false;
  final _items = <_Typed>[];
  final _costs = <_Typed>[];
  final _attached = <PickedDocument>[];
  Withholding? _withholding;
  var _vat = false;
  var _remember = true;
  CalendarDate? _due;
  var _showAll = false;
  var _saving = false;
  final _form = GlobalKey<FormState>();

  /// Whether Save was tapped with something missing, so the form shows
  /// what to fix as it changes.
  var _checked = false;

  CalendarDate get _today => CalendarDate.local(ref.read(clockProvider)());

  @override
  void initState() {
    super.initState();
    _due = _today.addDays(14);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadClient());
  }

  @override
  void dispose() {
    _client.dispose();
    _notes.dispose();
    for (final t in [..._items, ..._costs]) {
      t.dispose();
    }
    super.dispose();
  }

  String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

  /// The client's hours not billed yet, and how they handle withholding.
  Future<void> _loadClient() async {
    final client = _client.text.trim();
    if (client.isEmpty) {
      setState(() => _unbilled = const []);
      return;
    }
    final unbilled = await ref
        .read(hoursRepositoryProvider)
        .unbilled(client: client);
    final remembered = (await ref.read(
      clientWithholdingProvider.future,
    ))[client.toLowerCase()];
    final expects = (await ref.read(withholdingClientsProvider.future))
        .contains(client.toLowerCase());
    if (!mounted || client != _client.text.trim()) return;
    setState(() {
      _unbilled = unbilled;
      _from = unbilled.isEmpty ? null : unbilled.first.day;
      _to = _today;
      _projects
        ..clear()
        ..addAll({
          for (final e in unbilled)
            if (e.rateMinor != null) e.project,
        });
      _withholding ??=
          remembered ?? (expects ? Withholding.deducts : Withholding.none);
    });
  }

  List<HourEntry> get _chosenHours => [
    for (final e in _unbilled)
      if (_projects.contains(e.project) &&
          (_from == null || !e.day.isBefore(_from!)) &&
          !e.day.isAfter(_to))
        e,
  ];

  List<InvoiceLine> _feeLines() => switch (_billBy) {
    BillBy.hours => hoursLines(
      _chosenHours,
      _detail,
      plain: _plain,
      dayName: (d) => '${weekdayName(d).substring(0, 3)} ${shortDate(d)}',
    ),
    BillBy.items => [
      for (final t in _items)
        if (t.name.text.trim().isNotEmpty &&
            (AmountField.amountFrom(t.amount.text) ?? 0) > 0)
          () {
            final q = minutesFromQuantity(t.quantity.text);
            final price = AmountField.amountFrom(t.amount.text)!;
            return InvoiceLine(
              kind: InvoiceLineKind.fees,
              name: t.name.text.trim(),
              detail: q == 1000 ? null : '${_q(q)} × ${_plain(price)}',
              amountMinor: (price * q / 1000).round(),
              quantityMilli: q,
              unitMinor: price,
            );
          }(),
    ],
  };

  static String _q(int milliQ) => milliQ % 1000 == 0
      ? '${milliQ ~/ 1000}'
      : (milliQ / 1000).toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

  List<InvoiceLine> _costLines() => [
    for (final t in _costs)
      if (t.name.text.trim().isNotEmpty &&
          (AmountField.amountFrom(t.amount.text) ?? 0) > 0)
        InvoiceLine(
          kind: InvoiceLineKind.cost,
          name: t.name.text.trim(),
          amountMinor: AmountField.amountFrom(t.amount.text)!,
        ),
  ];

  InvoiceTotals _totals(TaxPack pack, {required bool vatRegistered}) =>
      invoiceTotals(
        feesMinor: _feeLines().fold(0, (sum, l) => sum + l.amountMinor),
        costsMinor: _costLines().fold(0, (sum, l) => sum + l.amountMinor),
        withholding: _withholding ?? Withholding.none,
        withholdingRate: pack.withholdingRate,
        vatRate: _vat && vatRegistered ? pack.vatRate : null,
      );

  Future<void> _editWithholding(TaxPack pack, bool vatRegistered) async {
    final fees = _feeLines().fold(0, (sum, l) => sum + l.amountMinor);
    final result = await showAppSheet<(Withholding, bool, bool)>(
      context: context,
      builder: (context) => _WithholdingSheet(
        client: _client.text.trim(),
        feesMinor: fees,
        rate: pack.withholdingRate,
        vatRate: pack.vatRate,
        vatRegistered: vatRegistered,
        value: _withholding ?? Withholding.none,
        vat: _vat,
        remember: _remember,
      ),
    );
    if (result == null) return;
    final (withholding, vat, remember) = result;
    setState(() {
      _withholding = withholding;
      _vat = vat;
      _remember = remember;
    });
  }

  Future<void> _attach() async {
    final picked = await showAttachSheet(context);
    if (picked == null || !mounted) return;
    // A cost not in Money yet is recorded the usual way: how it was paid
    // is asked in Spent.
    for (final a in picked) {
      final cost = a.costMinor;
      if (!a.recordCost || cost == null || cost <= 0 || !mounted) continue;
      await showBoughtSheet(
        context,
        costOnly: true,
        amountMinor: cost,
        note: a.costName,
      );
    }
    if (!mounted) return;
    setState(() {
      for (final a in picked) {
        _attached.add(a.file);
        final cost = a.costMinor;
        if (a.costName != null && cost != null && cost > 0) {
          _costs.add(
            _Typed()
              ..name.text = a.costName!
              ..amount.text = '${cost ~/ 100}',
          );
        }
      }
    });
  }

  Future<void> _save({required bool share}) async {
    if (!_form.currentState!.validate()) {
      setState(() => _checked = true);
      return;
    }
    final client = _client.text.trim();
    final pack = await ref.read(taxPackProvider.future);
    final tax = await ref.read(taxSettingsProvider.future);
    final fees = _feeLines();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final w = _withholding ?? Withholding.none;
      if (_remember) {
        await ref.read(clientWithholdingProvider.notifier).remember(client, w);
      }
      final id = await ref
          .read(invoicesControllerProvider)
          .create(
            InvoiceDraft(
              client: client,
              issuedOn: _today,
              dueOn: _due,
              billBy: _billBy,
              hoursDetail: _detail,
              timesheet: _billBy == BillBy.hours && _timesheet,
              withholding: w,
              totals: _totals(pack, vatRegistered: tax.vatRegistered),
              lines: [...fees, ..._costLines()],
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              hourIds: _billBy == BillBy.hours
                  ? [for (final e in _chosenHours) e.id]
                  : const [],
            ),
            attachments: _attached,
          );
      navigator.pop();
      if (share && navigator.mounted) {
        final views = await ref.refresh(invoicesProvider.future);
        final view = views.where((v) => v.invoice.id == id).firstOrNull;
        if (view != null && navigator.mounted) {
          await showShareInvoiceSheet(navigator.context, view);
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final loadedPack = ref.watch(taxPackProvider);
    final loadedTax = ref.watch(taxSettingsProvider);
    final pack = loadedPack.value;
    final tax = loadedTax.value;
    final clients = ref.watch(hourClientsProvider).value ?? const {};
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final label = theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    if (pack == null || tax == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New invoice')),
        body: loadedPack.hasError || loadedTax.hasError
            ? ErrorView(
                'Your tax settings could not load.',
                onRetry: () => ref
                  ..invalidate(taxPackProvider)
                  ..invalidate(taxSettingsProvider),
              )
            : const LoadingView(),
      );
    }
    final totals = _totals(pack, vatRegistered: tax.vatRegistered);
    final feeLines = _feeLines();
    final costLines = _costLines();
    final byProj = <String?, List<HourEntry>>{};
    for (final e in _unbilled) {
      byProj.putIfAbsent(e.project, () => []).add(e);
    }
    final w = _withholding ?? Withholding.none;
    final hours = _chosenHours.fold(0, (sum, e) => sum + e.minutes);

    Widget dateField(
      String text,
      CalendarDate? value,
      ValueChanged<CalendarDate> set,
    ) => Expanded(
      child: DateField(
        label: text,
        value: value,
        firstDate: CalendarDate(today.year - 2, 1, 1),
        lastDate: CalendarDate(today.year + 1, 1, 1),
        onChanged: (d) {
          if (d != null) set(d);
        },
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('New invoice')),
      body: Form(
        key: _form,
        autovalidateMode: _checked
            ? AutovalidateMode.always
            : AutovalidateMode.disabled,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _client.text),
              optionsBuilder: (v) {
                final q = v.text.trim().toLowerCase();
                if (q.isEmpty) return const [];
                return clients.keys.where(
                  (c) => c.toLowerCase().contains(q) && c.toLowerCase() != q,
                );
              },
              onSelected: (c) {
                _client.text = c;
                _loadClient();
              },
              fieldViewBuilder: (context, controller, focus, submit) =>
                  TextFormField(
                    key: const Key('invoice-client'),
                    controller: controller,
                    focusNode: focus,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Client'),
                    validator: (t) => (t ?? '').trim().isEmpty
                        ? 'Enter the client, such as Bidii Traders Ltd.'
                        : null,
                    onChanged: (t) {
                      _client.text = t;
                      _withholding = null;
                      _loadClient();
                    },
                  ),
            ),
            const SizedBox(height: 16),
            Text('Bill by', style: label),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AdaptiveSegmented<BillBy>(
                key: const Key('invoice-bill-by'),
                name: 'Bill by',
                segments: [for (final b in BillBy.values) (b, b.label)],
                segmentKey: (b) => Key('bill-by-${b.name}'),
                selected: _billBy,
                onChanged: (b) => setState(() {
                  _billBy = b;
                  if (b == BillBy.items && _items.isEmpty) {
                    _items.add(_Typed());
                  }
                }),
              ),
            ),
            const SizedBox(height: 12),
            if (_billBy == BillBy.hours) ...[
              Row(
                children: [
                  dateField('From', _from, (d) => setState(() => _from = d)),
                  const SizedBox(width: 12),
                  dateField('To', _to, (d) => setState(() => _to = d)),
                ],
              ),
              const SectionLabel('Hours not billed yet'),
              if (byProj.isEmpty)
                Text(
                  _client.text.trim().isEmpty
                      ? 'Choose the client to see their hours.'
                      : 'Hours you log for this client show here.',
                  style: muted,
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final MapEntry(key: project, value: list)
                          in byProj.entries)
                        () {
                          final m = list.fold(0, (sum, e) => sum + e.minutes);
                          final days = {for (final e in list) e.day}.length;
                          final rate = list
                              .map((e) => e.rateMinor)
                              .whereType<int>()
                              .firstOrNull;
                          final amount = list.fold(
                            0,
                            (sum, e) => sum + e.amountMinor,
                          );
                          return CheckboxListTile(
                            key: Key('invoice-project-${project ?? 'none'}'),
                            controlAffinity: ListTileControlAffinity.leading,
                            value: _projects.contains(project),
                            onChanged: (on) => setState(() {
                              on ?? false
                                  ? _projects.add(project)
                                  : _projects.remove(project);
                            }),
                            title: Text(project ?? 'Hours'),
                            subtitle: Text(
                              [
                                '${hoursText(m)} h on $days ${days == 1 ? 'day' : 'days'}',
                                if (rate != null) '${_plain(rate)} an hour',
                                if (rate != null)
                                  _plain(amount)
                                else
                                  'bill later',
                              ].join(' · '),
                              style: muted,
                            ),
                          );
                        }(),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Text('Show hours on the invoice', style: label),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ChoiceMenu<HoursDetail>(
                  key: const Key('hours-detail'),
                  name: 'Show hours on the invoice',
                  options: [for (final d in HoursDetail.values) (d, d.label)],
                  value: _detail,
                  itemKey: (d) => Key('hours-detail-${d.name}'),
                  onChanged: (d) => setState(() => _detail = d),
                ),
              ),
              if (feeLines.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  key: const Key('invoice-preview'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel(
                        'Preview',
                        padding: EdgeInsets.fromLTRB(
                          Layout.cardPadding,
                          Layout.cardPadding,
                          Layout.cardPadding,
                          0,
                        ),
                      ),
                      for (final l in _showAll ? feeLines : feeLines.take(3))
                        LabelValueRow(
                          label: l.name,
                          value: _plain(l.amountMinor),
                          detail: (l.detail ?? '').isEmpty ? null : l.detail,
                        ),
                      if (!_showAll && feeLines.length > 3)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: TextButton(
                            onPressed: () => setState(() => _showAll = true),
                            child: Text('${feeLines.length - 3} more'),
                          ),
                        ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              ],
              SwitchListTile.adaptive(
                key: const Key('invoice-timesheet'),
                contentPadding: EdgeInsets.zero,
                value: _timesheet,
                onChanged: (on) => setState(() => _timesheet = on),
                title: const Text('Add the full timesheet as a page'),
                subtitle: Text(
                  'Every entry, with day and project totals',
                  style: muted,
                ),
              ),
            ] else ...[
              for (final (i, t) in _items.indexed) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        key: Key('item-name-$i'),
                        controller: t.name,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(labelText: 'What'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      child: TextField(
                        key: Key('item-quantity-$i'),
                        controller: t.quantity,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'How many',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: AmountField(
                        key: Key('item-price-$i'),
                        controller: t.amount,
                        label: 'Price',
                        allowZero: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const Key('invoice-add-item'),
                  onPressed: () => setState(() => _items.add(_Typed())),
                  child: const Text('Add a line'),
                ),
              ),
            ],
            FormField<void>(
              key: const Key('invoice-what-to-bill'),
              validator: (_) => feeLines.isNotEmpty
                  ? null
                  : _billBy == BillBy.hours
                  ? 'Choose the hours to bill, or bill by items.'
                  : 'Enter what to bill and its price, such as Strategy, '
                        '15,000.',
              builder: (field) => field.errorText == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        field.errorText!,
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            for (final (i, t) in _costs.indexed) ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      key: Key('cost-name-$i'),
                      controller: t.name,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Cost passed on',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: AmountField(
                      key: Key('cost-amount-$i'),
                      controller: t.amount,
                      label: 'Amount',
                      allowZero: true,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('invoice-add-cost'),
                onPressed: () => setState(() => _costs.add(_Typed())),
                child: const Text(
                  'Add a cost passed on, such as software for the work',
                ),
              ),
            ),
            if (_attached.isNotEmpty) ...[
              const SectionLabel(
                'Attached',
                padding: EdgeInsets.fromLTRB(0, 8, 0, 8),
              ),
              Card(
                child: Column(
                  children: [
                    for (final a in _attached)
                      ListTile(
                        leading: Icon(
                          a.mimeType == 'application/pdf'
                              ? Icons.picture_as_pdf_outlined
                              : Icons.image_outlined,
                        ),
                        title: Text(a.name),
                        trailing: IconButton(
                          tooltip: 'Remove ${a.name}',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _attached.remove(a)),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const Key('invoice-attach'),
                onPressed: _attach,
                child: const Text(
                  'Attach a document, such as a receipt or the eTIMS invoice',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Due', style: label),
            const SizedBox(height: 8),
            DueDateChips(
              today: today,
              value: _due,
              onChanged: (d) => setState(() => _due = d),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  LabelValueRow(
                    label: 'Fees',
                    value: _plain(totals.feesShownMinor),
                    detail: _billBy == BillBy.hours
                        ? '${hoursText(hours)} hours'
                        : '${feeLines.length} ${feeLines.length == 1 ? 'line' : 'lines'}',
                  ),
                  if (costLines.isNotEmpty)
                    LabelValueRow(
                      label: 'Costs',
                      value: _plain(totals.costsMinor),
                      detail: costLines.map((l) => l.name).join(', '),
                    ),
                  if (totals.vatMinor > 0)
                    LabelValueRow(
                      label: 'VAT (${rateText(pack.vatRate)})',
                      value: _plain(totals.vatMinor),
                    ),
                  LabelValueRow(
                    label: 'Withholding tax',
                    value: totals.withheldMinor == 0
                        ? 'None'
                        : '-${_plain(totals.withheldMinor)}',
                    key: const Key('invoice-withholding'),
                    detail: switch (w) {
                      Withholding.none => 'Tap to set it for this client',
                      Withholding.deducts =>
                        'Client deducts ${rateText(pack.withholdingRate)} of fees',
                      Withholding.onTop =>
                        'Client pays ${rateText(pack.withholdingRate)} on top',
                    },
                    onTap: () => _editWithholding(pack, tax.vatRegistered),
                  ),
                  LabelValueRow(
                    label: 'To pay',
                    value: _plain(totals.toPayMinor),
                    key: const Key('invoice-to-pay'),
                    strong: true,
                    valueColor: colors.successText,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('invoice-notes'),
              controller: _notes,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
            const SizedBox(height: 16),
            ButtonPair(
              primary: FilledButton(
                key: const Key('invoice-preview-share'),
                onPressed: _saving ? null : () => _save(share: true),
                child: const Text('Preview and share'),
              ),
              secondary: OutlinedButton(
                key: const Key('invoice-save'),
                onPressed: _saving ? null : () => _save(share: false),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quantity in thousandths from what was typed; 1 when it is not a number.
int minutesFromQuantity(String text) {
  final v = double.tryParse(text.trim().replaceAll(',', '.'));
  if (v == null || v <= 0) return 1000;
  return (v * 1000).round();
}

/// Withholding tax on this invoice: none, deducted by the client, or paid
/// on top; remembered for the client; VAT for VAT-registered businesses.
class _WithholdingSheet extends StatefulWidget {
  const _WithholdingSheet({
    required this.client,
    required this.feesMinor,
    required this.rate,
    required this.vatRate,
    required this.vatRegistered,
    required this.value,
    required this.vat,
    required this.remember,
  });

  final String client;
  final int feesMinor;
  final BasisPoints rate;
  final BasisPoints vatRate;
  final bool vatRegistered;
  final Withholding value;
  final bool vat;
  final bool remember;

  @override
  State<_WithholdingSheet> createState() => _WithholdingSheetState();
}

class _WithholdingSheetState extends State<_WithholdingSheet> {
  late var _value = widget.value;
  late var _vat = widget.vat;
  late var _remember = widget.remember;

  String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final rate = rateText(widget.rate);
    final fees = widget.feesMinor;
    final deducted = invoiceTotals(
      feesMinor: fees,
      costsMinor: 0,
      withholding: Withholding.deducts,
      withholdingRate: widget.rate,
    );
    final onTop = invoiceTotals(
      feesMinor: fees,
      costsMinor: 0,
      withholding: Withholding.onTop,
      withholdingRate: widget.rate,
    );
    final client = widget.client.isEmpty ? 'this client' : widget.client;
    final options = [
      (Withholding.none, 'No withholding tax', 'They pay the full invoice.'),
      (
        Withholding.deducts,
        'Client deducts $rate',
        'They pay ${_plain(fees - deducted.withheldMinor)} for fees and send '
            'KRA ${_plain(deducted.withheldMinor)}. It counts towards your '
            'income tax.',
      ),
      (
        Withholding.onTop,
        'Client pays the $rate on top',
        'Fees show as ${_plain(onTop.feesShownMinor)}, so after they deduct '
            '${_plain(onTop.withheldMinor)} you still get ${_plain(fees)}.',
      ),
    ];
    return SheetBody(
      title: 'Withholding tax',
      subtitle: 'Fees of ${_plain(fees)} for $client',
      children: [
        RadioGroup<Withholding>(
          groupValue: _value,
          onChanged: (v) => setState(() => _value = v ?? _value),
          child: Column(
            children: [
              for (final (value, title, detail) in options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Layout.panelRadius),
                      side: BorderSide(
                        color: _value == value
                            ? theme.colorScheme.primary
                            : colors.border,
                        width: _value == value ? 2 : 1,
                      ),
                    ),
                    child: RadioListTile<Withholding>(
                      key: Key('withholding-${value.name}'),
                      value: value,
                      title: Text(title),
                      subtitle: Text(detail),
                    ),
                  ),
                ),
            ],
          ),
        ),
        SwitchListTile.adaptive(
          key: const Key('withholding-remember'),
          contentPadding: EdgeInsets.zero,
          value: _remember,
          onChanged: (on) => setState(() => _remember = on),
          title: Text('Remember for $client'),
        ),
        SwitchListTile.adaptive(
          key: const Key('withholding-vat'),
          contentPadding: EdgeInsets.zero,
          value: _vat && widget.vatRegistered,
          onChanged: widget.vatRegistered
              ? (on) => setState(() => _vat = on)
              : null,
          title: Text('Add VAT (${rateText(widget.vatRate)})'),
          subtitle: Text(
            widget.vatRegistered
                ? 'For VAT-registered businesses.'
                : 'For VAT-registered businesses. Turn it on in Tax '
                      'settings.',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('withholding-done'),
          onPressed: () => Navigator.pop(context, (_value, _vat, _remember)),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
