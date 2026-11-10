import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../domain/stock/stock.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/sections.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import 'measure_sheet.dart';

/// Add an item: a product with its price, unit, cost and stock, or a
/// service with its price. With [servicesOnly], it is always a service.
Future<bool?> showItemSheet(
  BuildContext context, {
  bool servicesOnly = false,
}) => showAppSheet<bool>(
  context: context,
  builder: (context) => _ItemSheet(servicesOnly: servicesOnly),
);

/// A quantity in a form, such as 10 or 0.5.
class QuantityField extends StatelessWidget {
  const QuantityField({
    required this.controller,
    required this.label,
    this.optional = false,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool optional;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    validator: (text) {
      final t = (text ?? '').trim();
      if (t.isEmpty) return optional ? null : 'Enter how much, such as 10.';
      return quantityFrom(t) == null ? 'Enter a number, such as 0.5.' : null;
    },
  );
}

class _ItemSheet extends ConsumerStatefulWidget {
  const _ItemSheet({required this.servicesOnly});

  final bool servicesOnly;

  @override
  ConsumerState<_ItemSheet> createState() => _ItemSheetState();
}

class _ItemSheetState extends ConsumerState<_ItemSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _unit = TextEditingController();
  final _cost = TextEditingController();
  final _stock = TextEditingController();
  final _warn = TextEditingController();
  final _group = TextEditingController();
  late var _kind = widget.servicesOnly ? ItemKind.service : ItemKind.product;
  final _measures = <MeasureDraft>[];
  var _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _price, _unit, _cost, _stock, _warn, _group]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final product = _kind == ItemKind.product;
      final price = AmountField.amountFrom(_price.text);
      final stock = ref.read(stockRepositoryProvider);
      final id = await stock.add(
        kind: _kind,
        name: _name.text,
        at: ref.read(clockProvider)(),
        unit: _unit.text,
        priceMinor: price == null || price == 0 ? null : price,
        costMinor: product ? AmountField.amountFrom(_cost.text) ?? 0 : 0,
        stockMilli: product ? quantityFrom(_stock.text) ?? 0 : 0,
        warnBelowMilli: product ? quantityFrom(_warn.text) : null,
        grouping: _group.text.trim().isEmpty ? null : _group.text.trim(),
      );
      if (product && _unit.text.trim().isNotEmpty) {
        for (final m in _measures) {
          await stock.addMeasure(
            id,
            name: m.name,
            units: m.units,
            bases: m.bases,
            priceMinor: m.priceMinor,
          );
        }
      }
      navigator.pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _money(int minor) => formatMoney(Money(minor));

  Future<void> _measure({MeasureDraft? existing, bool pack = false}) async {
    final unit = _unit.text.trim();
    final price = AmountField.amountFrom(_price.text);
    final draft = await showMeasureSheet(
      context,
      item: _name.text.trim().isEmpty ? 'This item' : _name.text.trim(),
      unit: unit,
      unitPriceMinor: price == null || price == 0 ? null : price,
      pack: pack,
      existing: existing,
    );
    if (draft == null || !mounted) return;
    setState(() {
      final at = existing == null ? -1 : _measures.indexOf(existing);
      if (draft.removed) {
        if (at >= 0) _measures.removeAt(at);
      } else if (at >= 0) {
        _measures[at] = draft;
      } else {
        _measures.add(draft);
      }
    });
  }

  /// A product: what it is counted in, its stock, every way it sells, and
  /// what it costs.
  List<Widget> _product(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              key: const Key('item-unit'),
              controller: _unit,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'You count it in',
                hintText: 'Bottle, kg, bunch',
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: QuantityField(
              key: const Key('item-stock'),
              controller: _stock,
              label: 'In stock now',
              optional: true,
            ),
          ),
        ],
      ),
      const SectionLabel('Sold as'),
      Card(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _capital(_unit.text.trim()).isEmpty
                              ? 'Each'
                              : _capital(_unit.text.trim()),
                          style: theme.textTheme.titleSmall,
                        ),
                        Text('The unit you count', style: muted),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: AmountField(
                      key: const Key('item-price'),
                      controller: _price,
                      label: 'Sells for',
                      allowZero: true,
                    ),
                  ),
                ],
              ),
            ),
            for (final m in _measures) ...[
              const Divider(height: 1),
              ListTile(
                key: Key('item-measure-${m.name}'),
                title: Text(m.name),
                subtitle: Text(_size(m), style: muted),
                trailing: Text(
                  m.priceMinor == null ? 'Bought only' : _money(m.priceMinor!),
                  style: AppTypography.rowAmount(theme.colorScheme.onSurface),
                ),
                onTap: () => _measure(existing: m),
              ),
            ],
            if (_unit.text.trim().isNotEmpty) ...[
              const Divider(height: 1),
              SellAnotherWayTile(
                key: const Key('item-add-measure'),
                onTap: _measure,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      AmountField(
        key: const Key('item-cost'),
        controller: _cost,
        label: _unit.text.trim().isEmpty
            ? 'You pay about, each'
            : 'You pay about, a ${_unit.text.trim().toLowerCase()}',
        allowZero: true,
      ),
      const SizedBox(height: 4),
      ListenableBuilder(
        listenable: _cost,
        builder: (context, _) =>
            Text(_costNote(), key: const Key('item-cost-note'), style: muted),
      ),
      const SizedBox(height: 12),
      QuantityField(
        key: const Key('item-warn'),
        controller: _warn,
        label: 'Warn me below',
        optional: true,
      ),
    ];
  }

  /// `30 in a bottle`, or for a pack `24 bottles`.
  String _size(MeasureDraft m) {
    final unit = _unit.text.trim().toLowerCase();
    return m.isPack
        ? '${m.bases} ${unitFor(unit, m.bases * milli)}'
        : '${m.units} in a $unit';
  }

  /// What the smallest way of selling costs, once the cost is known.
  String _costNote() {
    final cost = AmountField.amountFrom(_cost.text);
    final parts = [
      for (final m in _measures)
        if (!m.isPack) m,
    ]..sort((a, b) => b.units.compareTo(a.units));
    if (cost == null || cost == 0 || parts.isEmpty) {
      return 'Updated from what you pay each time you restock.';
    }
    final finest = parts.first;
    final word = finest.name.split(',').first.trim().toLowerCase();
    return 'Each $word then costs you about '
        '${_money((cost * finest.bases / finest.units / 100).round() * 100)}.';
  }

  @override
  Widget build(BuildContext context) {
    final product = _kind == ItemKind.product;
    Widget two(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    );
    return Form(
      key: _form,
      child: SheetBody(
        title: 'Add an item',
        children: [
          if (!widget.servicesOnly) ...[
            AdaptiveSegmented<ItemKind>(
              key: const Key('item-kind'),
              segments: const [
                (ItemKind.product, 'Product'),
                (ItemKind.service, 'Service'),
              ],
              selected: _kind,
              segmentKey: (kind) => Key('item-${kind.name}'),
              onChanged: (kind) => setState(() => _kind = kind),
            ),
            const SizedBox(height: 12),
          ],
          TextFormField(
            key: const Key('item-name'),
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Name'),
            validator: (t) => (t ?? '').trim().isEmpty
                ? 'Enter what it is, such as Tomatoes.'
                : null,
          ),
          const SizedBox(height: 12),
          if (product)
            ..._product(context)
          else
            two(
              AmountField(
                key: const Key('item-price'),
                controller: _price,
                label: 'Price (empty if it varies)',
                allowZero: true,
              ),
              TextFormField(
                key: const Key('item-unit'),
                controller: _unit,
                decoration: const InputDecoration(labelText: 'Per (optional)'),
              ),
            ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('item-group'),
            controller: _group,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Group on Sell (optional), such as Vegetables',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('item-save'),
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

String _capital(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
