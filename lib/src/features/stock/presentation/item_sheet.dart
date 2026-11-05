import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../domain/stock/stock.dart';
import '../../../shared/widgets/form_fields.dart';

/// Add an item: a product with its price, unit, cost and stock, or a
/// service with its price. With [servicesOnly], it is always a service.
Future<bool?> showItemSheet(
  BuildContext context, {
  bool servicesOnly = false,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: _ItemSheet(servicesOnly: servicesOnly),
      ),
    ),
  ),
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
      await ref
          .read(stockRepositoryProvider)
          .add(
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
      navigator.pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add an item', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (!widget.servicesOnly) ...[
            Wrap(
              spacing: 8,
              children: [
                for (final (kind, label) in [
                  (ItemKind.product, 'Product'),
                  (ItemKind.service, 'Service'),
                ])
                  ChoiceChip(
                    key: Key('item-${kind.name}'),
                    label: Text(label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
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
          two(
            AmountField(
              key: const Key('item-price'),
              controller: _price,
              label: product ? 'Sells for' : 'Price (empty if it varies)',
              allowZero: true,
            ),
            TextFormField(
              key: const Key('item-unit'),
              controller: _unit,
              decoration: InputDecoration(
                labelText: product
                    ? 'Per (kg, bunch, piece)'
                    : 'Per (optional)',
              ),
            ),
          ),
          if (product) ...[
            const SizedBox(height: 12),
            AmountField(
              key: const Key('item-cost'),
              controller: _cost,
              label: 'You pay about, a unit',
              allowZero: true,
            ),
            const SizedBox(height: 4),
            Text(
              'Updated from what you pay each time you restock.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            two(
              QuantityField(
                key: const Key('item-stock'),
                controller: _stock,
                label: 'In stock now',
                optional: true,
              ),
              QuantityField(
                key: const Key('item-warn'),
                controller: _warn,
                label: 'Warn me below',
                optional: true,
              ),
            ),
          ],
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
