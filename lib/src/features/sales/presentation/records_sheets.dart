import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/category_seeds.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../domain/debts/debt.dart';
import '../../../domain/people/people.dart';
import '../../../domain/spaces/space_categories.dart';
import '../../../domain/stock/measure.dart';
import '../../../domain/stock/stock.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
import '../../payees/presentation/category_picker.dart';
import '../../people/application/people_providers.dart';
import '../../spaces/application/spaces_providers.dart';
import '../../stock/application/stock_providers.dart';
import '../../stock/presentation/item_sheet.dart';
import '../../stock/presentation/measure_sheet.dart';
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
    showAppSheet<bool>(context: context, builder: (_) => child);

/// Bought: stock or a cost, paid now or later. With [costOnly], as for a
/// services business, there is no stock to choose.
Future<bool?> showBoughtSheet(
  BuildContext context, {
  bool costOnly = false,
  bool payLater = false,
  int? itemId,
  int? amountMinor,
  String? note,
}) => _sheet(
  context,
  _BoughtSheet(
    costOnly: costOnly,
    payLater: payLater,
    itemId: itemId,
    amountMinor: amountMinor,
    note: note,
  ),
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
  NavigatorState navigator, {
  required SalePaymentMethod method,
  required String what,
}) {
  navigator.pop(true);
  final waits =
      method == SalePaymentMethod.mpesa || method == SalePaymentMethod.bank;
  showNote(
    navigator.context,
    waits
        ? '$what saved. It will match the ${methodName(method)} message '
              'when it comes.'
        : '$what saved.',
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
    child: Notice(
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
    this.amountMinor,
    this.note,
  });

  final bool costOnly;
  final bool payLater;

  /// The product to restock, to start with.
  final int? itemId;

  /// The amount and what it was for, to start with, such as from an
  /// attached receipt.
  final int? amountMinor;
  final String? note;

  @override
  ConsumerState<_BoughtSheet> createState() => _BoughtSheetState();
}

class _BoughtSheetState extends ConsumerState<_BoughtSheet> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(
    text: widget.amountMinor == null ? '' : '${widget.amountMinor! ~/ 100}',
  );
  late final _note = TextEditingController(text: widget.note);
  final _supplier = TextEditingController();
  final _quantity = TextEditingController();
  late var _stock = !widget.costOnly;
  late int? _itemId = widget.itemId;

  /// The pack it was bought in, such as a crate; null for one unit.
  int? _packId;
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
            quantityMilli: _stock && _itemId != null ? _boughtMilli() : null,
          );
      _saved(navigator, method: _method, what: 'Bought');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The packs [itemId] is bought in, such as crates.
  List<Measure> _packs(int? itemId) => [
    for (final m
        in ref.watch(measuresProvider).value?[itemId] ?? const <Measure>[])
      if (m.isPack) m,
  ];

  Measure? get _pack =>
      _packs(_itemId).where((m) => m.id == _packId).firstOrNull;

  /// What was bought, in thousandths of the item's unit.
  int? _boughtMilli() {
    final q = quantityFrom(_quantity.text);
    if (q == null) return null;
    return _pack?.baseMilli(q) ?? q;
  }

  /// Adds a pack size for [item], such as a crate of 24, and picks it.
  Future<void> _newPack(Item item) async {
    final draft = await showMeasureSheet(
      context,
      item: item.name,
      unit: item.unit!,
      unitPriceMinor: item.priceMinor,
      pack: true,
    );
    if (draft == null || draft.removed || !mounted) return;
    final id = await ref
        .read(stockRepositoryProvider)
        .addMeasure(
          item.id,
          name: draft.name,
          units: draft.units,
          bases: draft.bases,
          priceMinor: draft.priceMinor,
        );
    ref.invalidate(measuresProvider);
    if (mounted) setState(() => _packId = id);
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
      child: SheetBody(
        title: 'Bought',
        children: [
          if (!widget.costOnly) ...[
            AdaptiveSegmented<bool>(
              key: const Key('bought-kind'),
              segments: const [(true, 'Stock'), (false, 'A cost')],
              selected: _stock,
              segmentKey: (stock) =>
                  Key(stock ? 'bought-stock' : 'bought-cost'),
              onChanged: (stock) => setState(() => _stock = stock),
            ),
            const SizedBox(height: 12),
          ],
          if (!_stock) ...[
            FormField<int>(
              validator: (_) => _costId == null
                  ? 'Choose a category, such as Transport.'
                  : null,
              builder: (field) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CategorySelectorField(
                    key: const Key('bought-category'),
                    // It is needed to save, so not "Choose later".
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
            if (products.length > 2)
              ChoiceMenu<int?>(
                key: const Key('bought-item'),
                name: 'Item',
                expand: true,
                options: [
                  (null, 'Other stock'),
                  for (final p in products) (p.id, p.name),
                ],
                value: item?.id,
                itemKey: (id) => Key('bought-item-${id ?? 'other'}'),
                onChanged: (id) => setState(() {
                  _itemId = id;
                  _packId = null;
                }),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in products)
                    ChoiceChip(
                      key: Key('bought-item-${p.id}'),
                      label: Text(p.name),
                      selected: _itemId == p.id,
                      onSelected: (on) => setState(() {
                        _itemId = on ? p.id : null;
                        _packId = null;
                      }),
                    ),
                ],
              ),
            const SizedBox(height: 12),
            if (item != null && item.unit == null) ...[
              QuantityField(
                key: const Key('bought-quantity'),
                controller: _quantity,
                label: 'How many',
              ),
              const SizedBox(height: 12),
            ] else if (item != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: QuantityField(
                      key: const Key('bought-quantity'),
                      controller: _quantity,
                      label: 'How many',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ChoiceMenu<int?>(
                          key: const Key('bought-of'),
                          name: 'Of',
                          expand: true,
                          options: [
                            (null, _capital(unitFor(item.unit!, 2 * milli))),
                            for (final p in _packs(item.id))
                              (
                                p.id,
                                '${_capital(plural(p.word, 2))} of '
                                    '${p.bases ~/ p.units}',
                              ),
                            (_newPackOption, 'A new pack size'),
                          ],
                          value: _pack?.id,
                          itemKey: (id) => Key('bought-of-${id ?? 'unit'}'),
                          onChanged: (id) => id == _newPackOption
                              ? _newPack(item)
                              : setState(() => _packId = id),
                        ),
                      ],
                    ),
                  ),
                ],
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
                final q = _boughtMilli();
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
                final pack = _pack;
                if (pack != null && unit != null) {
                  final word = unit.toLowerCase();
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Notice(
                      key: const Key('bought-average'),
                      'Stock goes to ${inPacks(after, pack, unit: unit)} '
                      '(${quantityText(after)} ${unitFor(word, after)}). '
                      'Each $word now costs you about '
                      '${formatMoney(Money((average / 100).round() * 100))}.',
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Notice(
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
          MethodMenu(
            keyPrefix: 'bought-way',
            name: 'Payment',
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

/// The "A new pack size" row in the Of menu.
const _newPackOption = -1;

String _capital(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

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

  String _owingLabel(_Owing who) =>
      '${who.name} · '
      '${formatMoney(Money(who.owedMinor), withCurrency: false)}';

  void _pick(_Owing who) => setState(() {
    _customer = who.name;
    _amount.text = formatMoney(Money(who.owedMinor), withCurrency: false);
  });

  Future<void> _save(int owed) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(salesControllerProvider)
          .gotPaid(
            customer: _customer!,
            amountMinor: AmountField.amountFrom(_amount.text)!,
            method: _method,
          );
      _saved(navigator, method: _method, what: 'Payment');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owing = _owing();
    final start =
        owing
            .where(
              (o) =>
                  o.name.toLowerCase() == widget.customer?.trim().toLowerCase(),
            )
            .firstOrNull ??
        owing.firstOrNull;
    if (_customer == null && start != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _customer == null) _pick(start);
      });
    }
    final owed = owing
        .where((o) => o.name == _customer)
        .fold(0, (sum, o) => sum + o.owedMinor);

    return Form(
      key: _form,
      child: SheetBody(
        title: 'Got paid',
        children: [
          if (owing.isEmpty)
            Text(
              'Customers who owe you show here. Sell on credit and they '
              'appear, ready to pay.',
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            _label(context, 'Who paid?'),
            if (owing.length > 2)
              ChoiceMenu<String>(
                key: const Key('got-paid-who'),
                name: 'Who paid',
                expand: true,
                options: [
                  for (final who in owing) (who.name, _owingLabel(who)),
                ],
                // Till the first frame picks them, the one it will start with.
                value: _customer ?? start!.name,
                itemKey: (name) => Key('got-paid-$name'),
                onChanged: (name) =>
                    _pick(owing.firstWhere((o) => o.name == name)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final who in owing)
                    ChoiceChip(
                      key: Key('got-paid-${who.name}'),
                      label: Text(_owingLabel(who)),
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
            MethodMenu(
              keyPrefix: 'got-paid-way',
              name: 'Payment',
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

  String _owedLabel(Debt debt) =>
      '${debt.lender} · '
      '${formatMoney(Money(debt.balanceMinor), withCurrency: false)}';

  void _pick(Debt debt) => setState(() {
    _debt = debt;
    _amount.text = formatMoney(Money(debt.balanceMinor), withCurrency: false);
  });

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final debt = _debt!;
    final navigator = Navigator.of(context);
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
      _saved(navigator, method: _method, what: 'Payment');
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
    final start =
        owed.where((d) => d.id == widget.debtId).firstOrNull ??
        owed.firstOrNull;
    if (_debt == null && start != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _debt == null) _pick(start);
      });
    }
    return Form(
      key: _form,
      child: SheetBody(
        title: 'Paid a supplier',
        children: [
          if (owed.isEmpty)
            Text(
              'Suppliers you owe show here. Buy with Pay later in Bought, '
              'and pay them from here.',
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            _label(context, 'Who did you pay?'),
            if (owed.length > 2)
              ChoiceMenu<int>(
                key: const Key('paid-who'),
                name: 'Who you paid',
                expand: true,
                options: [for (final d in owed) (d.id, _owedLabel(d))],
                // Till the first frame picks it, the one it will start with.
                value: _debt?.id ?? start!.id,
                itemKey: (id) => Key('paid-$id'),
                onChanged: (id) => _pick(owed.firstWhere((d) => d.id == id)),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in owed)
                    ChoiceChip(
                      key: Key('paid-${d.id}'),
                      label: Text(_owedLabel(d)),
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
            MethodMenu(
              keyPrefix: 'paid-way',
              name: 'Payment',
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

/// When money is due, as one drop-down: any time, today, in a week, or a
/// picked date. Null is any time. It opens by the key `due`, and each choice
/// is `due-<choice>`, such as `due-inAWeek`.
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
    final due = value;
    final choice = due == null
        ? _Due.anyTime
        : due == today
        ? _Due.today
        : due == week
        ? _Due.inAWeek
        : _Due.date;
    DateTime asDay(CalendarDate d) => DateTime(d.year, d.month, d.day);
    return ChoiceMenu<_Due>(
      key: const Key('due'),
      name: 'Due',
      expand: true,
      options: [
        (_Due.anyTime, 'Any time'),
        (_Due.today, 'Today'),
        (_Due.inAWeek, 'In a week'),
        (
          _Due.date,
          choice == _Due.date
              ? dayLabel(due!, thisYear: today.year)
              : 'Choose a date',
        ),
      ],
      value: choice,
      itemKey: (d) => Key('due-${d.name}'),
      onChanged: (d) async {
        switch (d) {
          case _Due.anyTime:
            onChanged(null);
          case _Due.today:
            onChanged(today);
          case _Due.inAWeek:
            onChanged(week);
          case _Due.date:
            final chosen = await pickDate(
              context,
              initialDate: asDay(due ?? week),
              firstDate: asDay(today),
              lastDate: asDay(today.addDays(366)),
            );
            if (chosen != null) {
              onChanged(CalendarDate(chosen.year, chosen.month, chosen.day));
            }
        }
      },
    );
  }
}

/// The choices in [DueDateChips].
enum _Due { anyTime, today, inAWeek, date }

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
    setState(() => _saving = true);
    try {
      await ref
          .read(payYourselfControllerProvider)
          .payYourself(
            amountMinor: AmountField.amountFrom(_amount.text)!,
            method: _method,
            as: _as,
          );
      _saved(navigator, method: _method, what: 'Pay');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profit = ref.watch(spaceSummaryProvider).value?.figureMinor;
    return Form(
      key: _form,
      child: SheetBody(
        title: 'Pay yourself',
        subtitle:
            'Money you take for yourself. It leaves the business and shows '
            'as income in Personal.',
        children: [
          AmountField(
            key: const Key('pay-yourself-amount'),
            controller: _amount,
            label: 'Amount',
          ),
          const SizedBox(height: 16),
          _label(context, 'From'),
          MethodMenu(
            keyPrefix: 'pay-yourself-from',
            name: 'From',
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
          AdaptiveSegmented<PersonalPayAs>(
            key: const Key('pay-yourself-as'),
            name: 'Into Personal as',
            segments: [for (final a in PersonalPayAs.values) (a, a.label)],
            selected: _as,
            segmentKey: (a) => Key('pay-yourself-as-${a.name}'),
            onChanged: (a) => setState(() => _as = a),
          ),
          if (profit != null)
            ListenableBuilder(
              listenable: _amount,
              builder: (context, _) {
                final amount = AmountField.amountFrom(_amount.text) ?? 0;
                final left = profit - amount;
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Notice(
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
