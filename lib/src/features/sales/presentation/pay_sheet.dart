import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../theme/pesa_colors.dart';
import '../../lending/application/lending_providers.dart';
import '../application/sales_providers.dart';

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
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: PaySheet(totalMinor: totalMinor, note: note),
  ),
);

class PaySheet extends ConsumerStatefulWidget {
  const PaySheet({required this.totalMinor, this.note, super.key});

  final int totalMinor;
  final String? note;

  @override
  ConsumerState<PaySheet> createState() => _PaySheetState();
}

/// When a customer on credit said they would pay.
enum _PayBy { today, inAWeek, date }

/// Customers who owe already, offered by name on a credit sale.
const _customerSuggestions = 5;

class _PaySheetState extends ConsumerState<PaySheet> {
  final _form = GlobalKey<FormState>();
  var _way = PayWay.cash;
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
      return [SalePart(method, widget.totalMinor)];
    }
    final now = _nowMinor;
    return [
      SalePart(_nowWay, now),
      SalePart(_restWay, widget.totalMinor - now),
    ];
  }

  Future<void> _done() async {
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
            credit: _needsCustomer
                ? CreditTerms(
                    customer: _customer.text.trim(),
                    dueDate: _dueDate(today),
                  )
                : null,
          );
      navigator.pop(true);
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
    final lent = ref.watch(lendingOverviewProvider).value?.lent ?? const [];
    final customers = {for (final l in lent) l.person}.toList();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pay ${_kes(widget.totalMinor)}',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.note ?? 'Other sale',
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                  Text(
                    formatMoney(Money(widget.totalMinor), withCurrency: false),
                    style: theme.textTheme.bodyLarge,
                  ),
                ],
              ),
              const Divider(height: 28),
              Text(
                'How are they paying?',
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final way in PayWay.values)
                    ChoiceChip(
                      key: Key('pay-${way.name}'),
                      label: Text(way.label),
                      selected: _way == way,
                      onSelected: (_) => setState(() => _way = way),
                    ),
                ],
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
      _Change(controller: _given, totalMinor: widget.totalMinor),
    ],
    PayWay.mpesa || PayWay.bank => [
      _Note(
        'Waiting for the ${methodName(_way.method!)} message for '
        '${_kes(widget.totalMinor)}. It will match this sale on its own, '
        'or tap Done now.',
      ),
    ],
    PayWay.credit => _credit(context, today, customers),
    PayWay.split => [
      AmountField(
        key: const Key('pay-now'),
        controller: _now,
        label: 'Paid now',
        maxMinor: widget.totalMinor - 100,
      ),
      const SizedBox(height: 8),
      _MethodChips(
        keyPrefix: 'pay-now',
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
          final rest = widget.totalMinor - _nowMinor;
          return Text(
            rest > 0 && rest < widget.totalMinor
                ? 'The rest, ${_kes(rest)}'
                : 'The rest',
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: PesaColors.of(context).textMuted),
          );
        },
      ),
      const SizedBox(height: 8),
      _MethodChips(
        keyPrefix: 'pay-rest',
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
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Today'),
            selected: _payBy == _PayBy.today,
            onSelected: (_) => setState(() => _payBy = _PayBy.today),
          ),
          ChoiceChip(
            label: const Text('In a week'),
            selected: _payBy == _PayBy.inAWeek,
            onSelected: (_) => setState(() => _payBy = _PayBy.inAWeek),
          ),
          ChoiceChip(
            key: const Key('pay-by-date'),
            label: Text(
              _payBy == _PayBy.date && picked != null
                  ? dayLabel(picked, thisYear: today.year)
                  : 'Pick a date',
            ),
            selected: _payBy == _PayBy.date,
            onSelected: (_) async {
              DateTime asDay(CalendarDate d) =>
                  DateTime(d.year, d.month, d.day);
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
        ],
      ),
    ];
  }
}

class _MethodChips extends StatelessWidget {
  const _MethodChips({
    required this.keyPrefix,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String keyPrefix;
  final List<SalePaymentMethod> options;
  final SalePaymentMethod selected;
  final ValueChanged<SalePaymentMethod> onSelected;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final m in options)
        ChoiceChip(
          key: Key('$keyPrefix-${m.name}'),
          label: Text(methodLabel(m)),
          selected: selected == m,
          onSelected: (_) => onSelected(m),
        ),
    ],
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
        child: _Note(
          'Change: ${formatMoney(Money(given - totalMinor))}',
          key: const Key('pay-change'),
        ),
      );
    },
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key});

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
