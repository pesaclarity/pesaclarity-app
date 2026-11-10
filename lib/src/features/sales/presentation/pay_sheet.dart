import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../domain/people/people.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/stock/stock.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../theme/pesa_colors.dart';
import '../../documents/application/document_providers.dart';
import '../../documents/presentation/receipt_sheet.dart';
import '../../people/application/people_providers.dart';
import '../../printing/application/document_slips.dart';
import '../../printing/application/printing_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/sales_providers.dart';
import 'choose_payments_sheet.dart';

/// How a sale is paid, as Pay offers it.
enum PayWay {
  cash('Cash'),
  mpesa('M-Pesa'),
  bank('Bank'),
  credit('On credit'),
  split('Split');

  const PayWay(this.label);

  final String label;

  SalePaymentMethod? get method => switch (this) {
    PayWay.cash => SalePaymentMethod.cash,
    PayWay.mpesa => SalePaymentMethod.mpesa,
    PayWay.bank => SalePaymentMethod.bank,
    PayWay.credit => SalePaymentMethod.credit,
    PayWay.split => null,
  };
}

/// How [method] is labelled on its own: `Cash`, `On credit`.
String methodLabel(SalePaymentMethod method) => switch (method) {
  SalePaymentMethod.cash => 'Cash',
  SalePaymentMethod.mpesa => 'M-Pesa',
  SalePaymentMethod.bank => 'Bank',
  SalePaymentMethod.credit => 'On credit',
};

/// The name of [method] in a sentence: `M-Pesa`, `bank`.
String methodName(SalePaymentMethod method) => switch (method) {
  SalePaymentMethod.cash => 'cash',
  SalePaymentMethod.mpesa => 'M-Pesa',
  SalePaymentMethod.bank => 'bank',
  SalePaymentMethod.credit => 'credit',
};

/// Pay for a sale of [totalMinor]: how they are paying, then Done. Returns
/// true once the sale is saved.
Future<bool?> showPaySheet(
  BuildContext context, {
  required int totalMinor,
  String? note,
  PayWay initialWay = PayWay.cash,
  List<SaleLine> lines = const [],
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: PaySheet(
      totalMinor: totalMinor,
      note: note,
      initialWay: initialWay,
      lines: lines,
    ),
  ),
);

class PaySheet extends ConsumerStatefulWidget {
  const PaySheet({
    required this.totalMinor,
    this.note,
    this.initialWay = PayWay.cash,
    this.lines = const [],
    super.key,
  });

  final int totalMinor;
  final String? note;

  /// What is being sold, item by item; empty for a typed amount.
  final List<SaleLine> lines;

  /// Credit for work billed to pay later.
  final PayWay initialWay;

  @override
  ConsumerState<PaySheet> createState() => _PaySheetState();
}

/// When a customer on credit said they would pay.
enum _PayBy { today, inAWeek, date }

/// Customers who owe already, offered by name on a credit sale.
const _customerSuggestions = 5;

class _PaySheetState extends ConsumerState<PaySheet> {
  final _form = GlobalKey<FormState>();
  late var _way = widget.initialWay;
  late final _lines = [...widget.lines];

  /// The total: the lines as they stand, or the amount typed.
  int get _total => _lines.isEmpty
      ? widget.totalMinor
      : _lines.fold(0, (sum, l) => sum + l.totalMinor);

  /// [line] with [quantityMilli] of it, at its unit price.
  SaleLine _withQuantity(SaleLine line, int quantityMilli) {
    final unitPrice = line.quantityMilli == 0
        ? 0
        : (line.totalMinor * milli / line.quantityMilli).round();
    return SaleLine(
      itemId: line.itemId,
      measureId: line.measureId,
      name: line.name,
      quantityMilli: quantityMilli,
      totalMinor: costOf(quantityMilli, unitPrice),
    );
  }

  final _given = TextEditingController();
  final _customer = TextEditingController();
  final _now = TextEditingController();
  var _nowWay = SalePaymentMethod.cash;
  var _restWay = SalePaymentMethod.mpesa;
  var _payBy = _PayBy.inAWeek;
  CalendarDate? _picked;
  var _saving = false;

  @override
  void dispose() {
    _given.dispose();
    _customer.dispose();
    _now.dispose();
    super.dispose();
  }

  String _kes(int minor) => formatMoney(Money(minor));

  int get _nowMinor => AmountField.amountFrom(_now.text) ?? 0;

  bool get _needsCustomer =>
      _way == PayWay.credit ||
      (_way == PayWay.split && _restWay == SalePaymentMethod.credit);

  CalendarDate? _dueDate(CalendarDate today) => switch (_payBy) {
    _PayBy.today => today,
    _PayBy.inAWeek => today.addDays(7),
    _PayBy.date => _picked,
  };

  List<SalePart> _parts() {
    if (_way case PayWay(:final method?)) {
      return [SalePart(method, _total)];
    }
    final now = _nowMinor;
    return [SalePart(_nowWay, now), SalePart(_restWay, _total - now)];
  }

  Future<void> _done({bool choose = false}) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final today = CalendarDate.local(ref.read(clockProvider)());
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final parts = _parts();
      final outcome = await ref
          .read(salesControllerProvider)
          .sell(
            parts,
            note: widget.note,
            lines: _lines,
            credit: _needsCustomer
                ? CreditTerms(
                    customer: _customer.text.trim(),
                    dueDate: _dueDate(today),
                  )
                : null,
          );
      // A business offers the receipt, unless the owner turned it off.
      final business = ref.read(activeSpaceProvider).kind == SpaceKind.business;
      final offer =
          business &&
          (await ref.read(documentSettingsProvider.future)).offerReceipt;
      // And prints it on the counter printer when the owner asked for that.
      if (business && await ref.read(slipPrinterProvider).printsAfterSale()) {
        final receipt = await ref
            .read(receiptMakerProvider)
            .receiptFor(outcome.saleId);
        if (receipt != null) {
          unawaited(
            ref
                .read(slipPrinterProvider)
                .onCounter(slipForReceipt(receipt))
                .catchError((Object _) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'The sale is saved. To print its receipt, turn the '
                        'printer on, keep it close, then tap Print.',
                      ),
                    ),
                  );
                }),
          );
        }
      }
      navigator.pop(true);
      final waiting = outcome.waiting.firstOrNull;
      if (choose && waiting != null && navigator.mounted) {
        await showChoosePaymentsSheet(navigator.context, waiting);
        return;
      }
      if (offer && navigator.mounted) {
        await showReceiptSheet(navigator.context, outcome.saleId);
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(_savedMessage(parts, outcome))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _savedMessage(List<SalePart> parts, SaleOutcome outcome) {
    final matched = outcome.matched.firstOrNull;
    if (matched != null) {
      final who = matched.payeeName ?? matched.counterpartyName;
      return 'Sale saved. Matched the payment'
          '${who == null ? '' : ' from $who'} at '
          '${formatTime(matched.occurredAt)}.';
    }
    final waiting = parts
        .where(
          (p) =>
              p.method == SalePaymentMethod.mpesa ||
              p.method == SalePaymentMethod.bank,
        )
        .firstOrNull;
    if (waiting != null) {
      return 'Sale saved. It will match the ${methodName(waiting.method)} '
          'message when it comes.';
    }
    return 'Sale saved.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    // Newest first, each name once.
    final customers = [
      for (final c
          in ref.watch(customersProvider).value ?? const <CustomerAccount>[])
        c.name,
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Pay ${_kes(_total)}', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 12),
              if (_lines.isEmpty)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.note ?? 'Other sale',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                    Text(
                      formatMoney(Money(_total), withCurrency: false),
                      style: theme.textTheme.bodyLarge,
                    ),
                  ],
                )
              else
                for (final (i, line) in _lines.indexed)
                  _LineRow(
                    key: Key('pay-line-$i'),
                    line: line,
                    onChanged: line.itemId == null
                        ? null
                        : (q) => setState(() {
                            if (q <= 0) {
                              _lines.removeAt(i);
                            } else {
                              _lines[i] = _withQuantity(line, q);
                            }
                          }),
                  ),
              const Divider(height: 28),
              Text(
                'How are they paying?',
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              ChoiceMenu<PayWay>(
                key: const Key('pay-way'),
                name: 'Payment',
                expand: true,
                options: [for (final way in PayWay.values) (way, way.label)],
                value: _way,
                itemKey: (way) => Key('pay-${way.name}'),
                onChanged: (way) => setState(() => _way = way),
              ),
              const SizedBox(height: 16),
              ..._details(context, today, customers),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('pay-done'),
                onPressed: _saving ? null : _done,
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _details(
    BuildContext context,
    CalendarDate today,
    List<String> customers,
  ) => switch (_way) {
    PayWay.cash => [
      AmountField(
        key: const Key('pay-given'),
        controller: _given,
        label: 'Cash given (optional)',
        allowZero: true,
      ),
      _Change(controller: _given, totalMinor: _total),
    ],
    PayWay.mpesa || PayWay.bank => [
      InfoNote(
        'Waiting for the ${methodName(_way.method!)} message for '
        '${_kes(_total)}. It will match this sale on its own, '
        'or tap Done now.',
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          key: const Key('pay-choose'),
          onPressed: _saving ? null : () => _done(choose: true),
          child: const Text(
            'Paid another amount, or in parts? Choose payments',
          ),
        ),
      ),
    ],
    PayWay.credit => _credit(context, today, customers),
    PayWay.split => [
      AmountField(
        key: const Key('pay-now'),
        controller: _now,
        label: 'Paid now',
        maxMinor: _total - 100,
      ),
      const SizedBox(height: 8),
      MethodMenu(
        keyPrefix: 'pay-now',
        name: 'Paid now',
        options: const [
          SalePaymentMethod.cash,
          SalePaymentMethod.mpesa,
          SalePaymentMethod.bank,
        ],
        selected: _nowWay,
        onSelected: (m) => setState(() {
          _nowWay = m;
          if (_restWay == m) {
            _restWay = m == SalePaymentMethod.mpesa
                ? SalePaymentMethod.cash
                : SalePaymentMethod.mpesa;
          }
        }),
      ),
      const SizedBox(height: 16),
      ListenableBuilder(
        listenable: _now,
        builder: (context, _) {
          final rest = _total - _nowMinor;
          return Text(
            rest > 0 && rest < _total ? 'The rest, ${_kes(rest)}' : 'The rest',
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: PesaColors.of(context).textMuted),
          );
        },
      ),
      const SizedBox(height: 8),
      MethodMenu(
        keyPrefix: 'pay-rest',
        name: 'The rest',
        options: [
          for (final m in SalePaymentMethod.values)
            if (m != _nowWay) m,
        ],
        selected: _restWay,
        onSelected: (m) => setState(() => _restWay = m),
      ),
      if (_restWay == SalePaymentMethod.credit) ...[
        const SizedBox(height: 16),
        ..._credit(context, today, customers),
      ],
    ],
  };

  List<Widget> _credit(
    BuildContext context,
    CalendarDate today,
    List<String> customers,
  ) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final picked = _picked;
    return [
      TextFormField(
        key: const Key('pay-customer'),
        controller: _customer,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Customer'),
        validator: (text) => (text ?? '').trim().isEmpty
            ? 'Enter who will pay, such as Otieno.'
            : null,
      ),
      if (customers.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in customers.take(_customerSuggestions))
              ActionChip(
                label: Text(c),
                onPressed: () => setState(() => _customer.text = c),
              ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      Text(
        'When will they pay?',
        style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
      ),
      const SizedBox(height: 8),
      ChoiceMenu<_PayBy>(
        key: const Key('pay-by'),
        name: 'Due',
        expand: true,
        options: [
          (_PayBy.today, 'Today'),
          (_PayBy.inAWeek, 'In a week'),
          (
            _PayBy.date,
            _payBy == _PayBy.date && picked != null
                ? dayLabel(picked, thisYear: today.year)
                : 'Pick a date',
          ),
        ],
        value: _payBy,
        itemKey: (by) => Key('pay-by-${by.name}'),
        onChanged: (by) async {
          if (by != _PayBy.date) {
            setState(() => _payBy = by);
            return;
          }
          DateTime asDay(CalendarDate d) => DateTime(d.year, d.month, d.day);
          final chosen = await pickDate(
            context,
            initialDate: asDay(picked ?? today.addDays(7)),
            firstDate: asDay(today),
            lastDate: asDay(today.addDays(366)),
          );
          if (chosen == null) return;
          setState(() {
            _picked = CalendarDate(chosen.year, chosen.month, chosen.day);
            _payBy = _PayBy.date;
          });
        },
      ),
    ];
  }
}

/// A drop-down of the ways of paying in [options]. It opens by the key
/// `<keyPrefix>-menu`, and each way is `<keyPrefix>-<method>`.
class MethodMenu extends StatelessWidget {
  const MethodMenu({
    required this.keyPrefix,
    required this.name,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.labelFor = methodLabel,
    super.key,
  });

  final String keyPrefix;

  /// What is being chosen, such as `Paid now`, for screen readers.
  final String name;
  final List<SalePaymentMethod> options;
  final SalePaymentMethod selected;
  final ValueChanged<SalePaymentMethod> onSelected;
  final String Function(SalePaymentMethod method) labelFor;

  @override
  Widget build(BuildContext context) => ChoiceMenu<SalePaymentMethod>(
    key: Key('$keyPrefix-menu'),
    name: name,
    expand: true,
    options: [for (final m in options) (m, labelFor(m))],
    value: selected,
    itemKey: (m) => Key('$keyPrefix-${m.name}'),
    onChanged: onSelected,
  );
}

/// The change for cash given, once it covers the sale.
class _Change extends StatelessWidget {
  const _Change({required this.controller, required this.totalMinor});

  final TextEditingController controller;
  final int totalMinor;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final given = AmountField.amountFrom(controller.text) ?? 0;
      if (given <= totalMinor) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: InfoNote(
          'Change: ${formatMoney(Money(given - totalMinor))}',
          key: const Key('pay-change'),
        ),
      );
    },
  );
}

/// A soft green note, such as what happens next.
class InfoNote extends StatelessWidget {
  const InfoNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.success.withValues(alpha: 0.25)),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

/// One line on Pay: the item, − and + (a tap on the amount types it), and
/// the line's total.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.onChanged, super.key});

  final SaleLine line;

  /// Null for a typed amount, which has no quantity to change.
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = onChanged;
    Widget step(IconData icon, String label, int by) => IconButton(
      tooltip: label,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        shape: const CircleBorder(),
        side: BorderSide(color: PesaColors.of(context).border),
      ),
      onPressed: change == null ? null : () => change(line.quantityMilli + by),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(line.name, style: theme.textTheme.bodyLarge)),
          if (change != null) ...[
            step(Icons.remove, 'One less', -milli),
            InkWell(
              onTap: () async {
                final text = await _askQuantity(context, line);
                final q = text == null ? null : quantityFrom(text);
                if (q != null) change(q);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  quantityText(line.quantityMilli),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            step(Icons.add, 'One more', milli),
          ],
          SizedBox(
            width: 72,
            child: Text(
              formatMoney(Money(line.totalMinor), withCurrency: false),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }

  static Future<String?> _askQuantity(BuildContext context, SaleLine line) {
    final controller = TextEditingController(
      text: quantityText(line.quantityMilli),
    );
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(line.name),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'How much, such as 0.5'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Done'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}
