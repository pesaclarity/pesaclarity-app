import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/category_seeds.dart';
import '../../../domain/debts/debt.dart';
import '../../../domain/people/people.dart';
import '../../../domain/spaces/space_categories.dart';
import '../../../domain/stock/stock.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../theme/pesa_colors.dart';
import '../../payees/presentation/category_picker.dart';
import '../../people/application/people_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import '../../stock/application/stock_providers.dart';
import '../../stock/presentation/item_sheet.dart';
import '../application/pay_yourself.dart';
import '../application/sales_providers.dart';
import 'pay_sheet.dart';

/// Ways money is paid now, for Got paid and Paid.
const _paidNow = [
  SalePaymentMethod.cash,
  SalePaymentMethod.mpesa,
  SalePaymentMethod.bank,
];

Future<bool?> _sheet(BuildContext context, Widget child) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: child,
          ),
        ),
      ),
    );

/// Bought: stock or a cost, paid now or later. With [costOnly], as for a
/// services business, there is no stock to choose.
Future<bool?> showBoughtSheet(
  BuildContext context, {
  bool costOnly = false,
  bool payLater = false,
  int? itemId,
}) => _sheet(
  context,
  _BoughtSheet(costOnly: costOnly, payLater: payLater, itemId: itemId),
);

/// Got paid: a customer pays some or all of what they owe.
Future<bool?> showGotPaidSheet(BuildContext context, {String? customer}) =>
    _sheet(context, _GotPaidSheet(customer: customer));

/// Pay yourself: money the owner takes for themselves, as income in
/// Personal.
Future<bool?> showPayYourselfSheet(BuildContext context) =>
    _sheet(context, const _PayYourselfSheet());

/// Paid: the business pays a supplier some or all of what it owes.
Future<bool?> showPaidSheet(BuildContext context, {int? debtId}) =>
    _sheet(context, _PaidSheet(debtId: debtId));

void _saved(
  NavigatorState navigator,
  ScaffoldMessengerState messenger, {
  required SalePaymentMethod method,
  required String what,
}) {
  navigator.pop(true);
  final waits =
      method == SalePaymentMethod.mpesa || method == SalePaymentMethod.bank;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        waits
            ? '$what saved. It will match the ${methodName(method)} message '
                  'when it comes.'
            : '$what saved.',
      ),
    ),
  );
}

Widget _label(BuildContext context, String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(
    text,
    style: Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: PesaColors.of(context).textMuted),
  ),
);

Widget _waitNote(SalePaymentMethod method, int amountMinor) => switch (method) {
  SalePaymentMethod.mpesa || SalePaymentMethod.bank => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: InfoNote(
      'It will match the ${methodName(method)} message for '
      '${formatMoney(Money(amountMinor))} when it comes.',
    ),
  ),
  _ => const SizedBox.shrink(),
};

class _BoughtSheet extends ConsumerStatefulWidget {
  const _BoughtSheet({
    required this.costOnly,
    required this.payLater,
    this.itemId,
  });

  final bool costOnly;
  final bool payLater;

  /// The product to restock, to start with.
  final int? itemId;

  @override
  ConsumerState<_BoughtSheet> createState() => _BoughtSheetState();
}

class _BoughtSheetState extends ConsumerState<_BoughtSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _supplier = TextEditingController();
  final _quantity = TextEditingController();
  late var _stock = !widget.costOnly;
  late int? _itemId = widget.itemId;
  int? _costId;
  late var _method = widget.payLater
      ? SalePaymentMethod.credit
      : SalePaymentMethod.cash;
  CalendarDate? _due;
  var _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _supplier.dispose();
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final category = _stock
          ? await ensureCategory(ref.read(appDatabaseProvider), stockSeed)
          : _costId!;
      final note = _note.text.trim();
      final supplier = _supplier.text.trim();
      await ref
          .read(salesControllerProvider)
          .bought(
            amountMinor: AmountField.amountFrom(_amount.text)!,
            method: _method,
            categoryId: category,
            supplier: supplier.isEmpty ? null : supplier,
            dueDate: _method == SalePaymentMethod.credit ? _due : null,
            note: note.isEmpty ? null : note,
            itemId: _stock ? _itemId : null,
            quantityMilli: _stock && _itemId != null
                ? quantityFrom(_quantity.text)
                : null,
          );
      _saved(navigator, messenger, method: _method, what: 'Bought');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final later = _method == SalePaymentMethod.credit;
    final products = [
      for (final i in ref.watch(itemsProvider).value ?? const <Item>[])
        if (i.isProduct) i,
    ];
    final item = _stock
        ? products.where((p) => p.id == _itemId).firstOrNull
        : null;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Bought', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          if (!widget.costOnly) ...[
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('bought-stock'),
                  label: const Text('Stock'),
                  selected: _stock,
                  onSelected: (_) => setState(() => _stock = true),
                ),
                ChoiceChip(
                  key: const Key('bought-cost'),
                  label: const Text('A cost'),
                  selected: !_stock,
                  onSelected: (_) => setState(() => _stock = false),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (!_stock) ...[
            FormField<int>(
              validator: (_) => _costId == null ? 'Choose what it was.' : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CategorySelectorField(
                    key: const Key('bought-category'),
                    label: 'What it was',
                    noneLabel: 'Choose',
                    selectedId: _costId,
                    allowType: (type) => type == CategoryType.expense,
                    onChanged: (id) => setState(() => _costId = id),
                  ),
                  if (field.errorText case final error?)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 12),
                      child: Text(
                        error,
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (_stock && products.isNotEmpty) ...[
            _label(context, 'Item'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in products)
                  ChoiceChip(
                    key: Key('bought-item-${p.id}'),
                    label: Text(p.name),
                    selected: _itemId == p.id,
                    onSelected: (on) =>
                        setState(() => _itemId = on ? p.id : null),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (item != null) ...[
              QuantityField(
                key: const Key('bought-quantity'),
                controller: _quantity,
                label: item.unit == null
                    ? 'How many'
                    : 'How much (${item.unit})',
              ),
              const SizedBox(height: 12),
            ],
          ],
          AmountField(
            key: const Key('bought-amount'),
            controller: _amount,
            label: item == null ? 'Amount' : 'You paid',
          ),
          if (item != null)
            ListenableBuilder(
              listenable: Listenable.merge([_amount, _quantity]),
              builder: (context, _) {
                final q = quantityFrom(_quantity.text);
                final paid = AmountField.amountFrom(_amount.text);
                if (q == null || q <= 0 || paid == null || paid <= 0) {
                  return const SizedBox.shrink();
                }
                final after = item.stockMilli + q;
                final average = newAverageCost(
                  stockMilli: item.stockMilli,
                  averageMinor: item.averageCostMinor,
                  quantityMilli: q,
                  paidMinor: paid,
                );
                final unit = item.unit;
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: InfoNote(
                    key: const Key('bought-average'),
                    'Stock goes to ${quantityText(after)}'
                    '${unit == null ? '' : ' ${unitFor(unit, after)}'}. '
                    '${item.name} now costs you '
                    '${formatMoney(Money(average), withCurrency: false)}'
                    '${unit == null ? ' each' : ' per $unit'} on average.',
                  ),
                );
              },
            ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('bought-note'),
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _stock
                  ? 'What you bought (optional)'
                  : 'Note (optional)',
            ),
          ),
          const SizedBox(height: 16),
          _label(context, 'How did you pay?'),
          MethodChips(
            keyPrefix: 'bought-way',
            options: SalePaymentMethod.values,
            labelFor: (m) =>
                m == SalePaymentMethod.credit ? 'Pay later' : methodLabel(m),
            selected: _method,
            onSelected: (m) => setState(() => _method = m),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('bought-supplier'),
            controller: _supplier,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: later ? 'Supplier' : 'Supplier (optional)',
            ),
            validator: (text) => later && (text ?? '').trim().isEmpty
                ? 'Enter who you will pay, such as Wakulima wholesaler.'
                : null,
          ),
          if (later) ...[
            const SizedBox(height: 16),
            _label(context, 'When will you pay?'),
            DueDateChips(
              today: today,
              value: _due,
              onChanged: (d) => setState(() => _due = d),
            ),
          ],
          ListenableBuilder(
            listenable: _amount,
            builder: (context, _) =>
                _waitNote(_method, AmountField.amountFrom(_amount.text) ?? 0),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('bought-save'),
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Someone who owes the business, by name, and how much in all.
typedef _Owing = ({String name, int owedMinor});

class _GotPaidSheet extends ConsumerStatefulWidget {
  const _GotPaidSheet({this.customer});

  /// The customer to start with.
  final String? customer;

  @override
  ConsumerState<_GotPaidSheet> createState() => _GotPaidSheetState();
}

class _GotPaidSheetState extends ConsumerState<_GotPaidSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  String? _customer;
  var _method = SalePaymentMethod.cash;
  var _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  List<_Owing> _owing() => [
    for (final c
        in ref.watch(customersProvider).value ?? const <CustomerAccount>[])
      if (c.owedMinor > 0) (name: c.name, owedMinor: c.owedMinor),
  ];

  void _pick(_Owing who) => setState(() {
    _customer = who.name;
    _amount.text = formatMoney(Money(who.owedMinor), withCurrency: false);
  });

  Future<void> _save(int owed) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(salesControllerProvider)
          .gotPaid(
            customer: _customer!,
            amountMinor: AmountField.amountFrom(_amount.text)!,
            method: _method,
          );
      _saved(navigator, messenger, method: _method, what: 'Payment');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owing = _owing();
    if (_customer == null && owing.isNotEmpty) {
      final start = owing
          .where(
            (o) =>
                o.name.toLowerCase() == widget.customer?.trim().toLowerCase(),
          )
          .firstOrNull;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _customer == null) _pick(start ?? owing.first);
      });
    }
    final owed = owing
        .where((o) => o.name == _customer)
        .fold(0, (sum, o) => sum + o.owedMinor);

    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Got paid', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (owing.isEmpty)
            Text(
              'Customers who owe you show here. Sell on credit and they '
              'appear, ready to pay.',
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            _label(context, 'Who paid?'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final who in owing)
                  ChoiceChip(
                    key: Key('got-paid-${who.name}'),
                    label: Text(
                      '${who.name} · '
                      '${formatMoney(Money(who.owedMinor), withCurrency: false)}',
                    ),
                    selected: _customer == who.name,
                    onSelected: (_) => _pick(who),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AmountField(
              key: const Key('got-paid-amount'),
              controller: _amount,
              label: 'Amount paid',
              maxMinor: owed > 0 ? owed : null,
            ),
            const SizedBox(height: 16),
            _label(context, 'How did they pay?'),
            MethodChips(
              keyPrefix: 'got-paid-way',
              options: _paidNow,
              selected: _method,
              onSelected: (m) => setState(() => _method = m),
            ),
            ListenableBuilder(
              listenable: _amount,
              builder: (context, _) =>
                  _waitNote(_method, AmountField.amountFrom(_amount.text) ?? 0),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('got-paid-save'),
              onPressed: _saving || _customer == null
                  ? null
                  : () => _save(owed),
              child: const Text('Save'),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaidSheet extends ConsumerStatefulWidget {
  const _PaidSheet({this.debtId});

  /// The supplier's debt to start with.
  final int? debtId;

  @override
  ConsumerState<_PaidSheet> createState() => _PaidSheetState();
}

class _PaidSheetState extends ConsumerState<_PaidSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  Debt? _debt;
  var _method = SalePaymentMethod.mpesa;
  var _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _pick(Debt debt) => setState(() {
    _debt = debt;
    _amount.text = formatMoney(Money(debt.balanceMinor), withCurrency: false);
  });

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final debt = _debt!;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(salesControllerProvider)
          .paid(
            debtId: debt.id,
            supplier: debt.lender,
            amountMinor: AmountField.amountFrom(_amount.text)!,
            method: _method,
          );
      _saved(navigator, messenger, method: _method, what: 'Payment');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owed = [
      for (final s
          in ref.watch(suppliersProvider).value ?? const <SupplierAccount>[])
        s.debt,
    ];
    if (_debt == null && owed.isNotEmpty) {
      final start = owed.where((d) => d.id == widget.debtId).firstOrNull;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _debt == null) _pick(start ?? owed.first);
      });
    }
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Paid a supplier', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (owed.isEmpty)
            Text(
              'Suppliers you owe show here. Buy with Pay later in Bought, '
              'and pay them from here.',
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            _label(context, 'Who did you pay?'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final d in owed)
                  ChoiceChip(
                    key: Key('paid-${d.id}'),
                    label: Text(
                      '${d.lender} · '
                      '${formatMoney(Money(d.balanceMinor), withCurrency: false)}',
                    ),
                    selected: _debt?.id == d.id,
                    onSelected: (_) => _pick(d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AmountField(
              key: const Key('paid-amount'),
              controller: _amount,
              label: 'Amount paid',
              maxMinor: _debt?.balanceMinor,
            ),
            const SizedBox(height: 16),
            _label(context, 'How did you pay?'),
            MethodChips(
              keyPrefix: 'paid-way',
              options: _paidNow,
              selected: _method,
              onSelected: (m) => setState(() => _method = m),
            ),
            ListenableBuilder(
              listenable: _amount,
              builder: (context, _) =>
                  _waitNote(_method, AmountField.amountFrom(_amount.text) ?? 0),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('paid-save'),
              onPressed: _saving || _debt == null ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ],
      ),
    );
  }
}

/// When money is due: today, in a week, or a picked date. Null is no date.
class DueDateChips extends StatelessWidget {
  const DueDateChips({
    required this.today,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final CalendarDate today;
  final CalendarDate? value;
  final ValueChanged<CalendarDate?> onChanged;

  @override
  Widget build(BuildContext context) {
    final week = today.addDays(7);
    final picked = value != null && value != today && value != week
        ? value
        : null;
    DateTime asDay(CalendarDate d) => DateTime(d.year, d.month, d.day);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('Today'),
          selected: value == today,
          onSelected: (on) => onChanged(on ? today : null),
        ),
        ChoiceChip(
          label: const Text('In a week'),
          selected: value == week,
          onSelected: (on) => onChanged(on ? week : null),
        ),
        ChoiceChip(
          label: Text(
            picked == null
                ? 'Pick a date'
                : dayLabel(picked, thisYear: today.year),
          ),
          selected: picked != null,
          onSelected: (_) async {
            final chosen = await pickDate(
              context,
              initialDate: asDay(value ?? week),
              firstDate: asDay(today),
              lastDate: asDay(today.addDays(366)),
            );
            if (chosen != null) {
              onChanged(CalendarDate(chosen.year, chosen.month, chosen.day));
            }
          },
        ),
      ],
    );
  }
}

class _PayYourselfSheet extends ConsumerStatefulWidget {
  const _PayYourselfSheet();

  @override
  ConsumerState<_PayYourselfSheet> createState() => _PayYourselfSheetState();
}

class _PayYourselfSheetState extends ConsumerState<_PayYourselfSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  var _method = SalePaymentMethod.mpesa;
  var _as = PersonalPayAs.salary;
  var _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(payYourselfControllerProvider)
          .payYourself(
            amountMinor: AmountField.amountFrom(_amount.text)!,
            method: _method,
            as: _as,
          );
      _saved(navigator, messenger, method: _method, what: 'Pay');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profit = ref.watch(spaceSummaryProvider).value?.figureMinor;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Pay yourself', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            'Money you take for yourself. It leaves the business and shows '
            'as income in Personal.',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: PesaColors.of(context).textMuted,
            ),
          ),
          const SizedBox(height: 16),
          AmountField(
            key: const Key('pay-yourself-amount'),
            controller: _amount,
            label: 'Amount',
          ),
          const SizedBox(height: 16),
          _label(context, 'From'),
          MethodChips(
            keyPrefix: 'pay-yourself-from',
            options: const [
              SalePaymentMethod.mpesa,
              SalePaymentMethod.bank,
              SalePaymentMethod.cash,
            ],
            labelFor: (m) => switch (m) {
              SalePaymentMethod.mpesa => 'Business M-Pesa',
              SalePaymentMethod.bank => 'Business bank',
              _ => methodLabel(m),
            },
            selected: _method,
            onSelected: (m) => setState(() => _method = m),
          ),
          const SizedBox(height: 16),
          _label(context, 'Into Personal as'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in PersonalPayAs.values)
                ChoiceChip(
                  key: Key('pay-yourself-as-${a.name}'),
                  label: Text(a.label),
                  selected: _as == a,
                  onSelected: (_) => setState(() => _as = a),
                ),
            ],
          ),
          if (profit != null)
            ListenableBuilder(
              listenable: _amount,
              builder: (context, _) {
                final amount = AmountField.amountFrom(_amount.text) ?? 0;
                final left = profit - amount;
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: InfoNote(
                    'Your business profit this month is '
                    '${formatMoney(Money(profit), withCurrency: false)}.'
                    '${amount > 0 && left >= 0 ? ' After this, ${formatMoney(Money(left), withCurrency: false)} stays in the business.' : ''}',
                  ),
                );
              },
            ),
          _waitNote(_method, AmountField.amountFrom(_amount.text) ?? 0),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('pay-yourself-save'),
            onPressed: _saving ? null : _save,
            child: const Text('Pay yourself'),
          ),
        ],
      ),
    );
  }
}
