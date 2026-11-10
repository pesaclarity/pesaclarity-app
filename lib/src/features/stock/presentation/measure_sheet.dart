import 'package:flutter/material.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/stock/measure.dart';
import '../../../domain/stock/stock.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../theme/pesa_colors.dart';
import '../../sales/presentation/pay_sheet.dart' show InfoNote;

/// A way of selling or buying, as filled in, before it is saved; or, with
/// [removed], the owner stopped using it.
class MeasureDraft {
  const MeasureDraft({
    required this.name,
    required this.units,
    required this.bases,
    this.priceMinor,
  }) : removed = false;

  const MeasureDraft.removed()
    : name = '',
      units = 1,
      bases = 1,
      priceMinor = null,
      removed = true;

  final String name;
  final int units;
  final int bases;
  final int? priceMinor;
  final bool removed;

  bool get isPack => bases > units;
}

/// Sell it another way: a measure smaller than [unit], such as a tot, or
/// with [pack] a pack of several, such as a crate. [item] names what it is
/// for, and [unitPriceMinor] what one [unit] sells for. With [existing] it
/// changes that one and can stop it.
Future<MeasureDraft?> showMeasureSheet(
  BuildContext context, {
  required String item,
  required String unit,
  required int? unitPriceMinor,
  bool pack = false,
  MeasureDraft? existing,
}) => showModalBottomSheet<MeasureDraft>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: _MeasureSheet(
          item: item,
          unit: unit,
          unitPriceMinor: unitPriceMinor,
          pack: existing?.isPack ?? pack,
          existing: existing,
        ),
      ),
    ),
  ),
);

class _MeasureSheet extends StatefulWidget {
  const _MeasureSheet({
    required this.item,
    required this.unit,
    required this.unitPriceMinor,
    required this.pack,
    required this.existing,
  });

  final String item;
  final String unit;
  final int? unitPriceMinor;
  final bool pack;
  final MeasureDraft? existing;

  @override
  State<_MeasureSheet> createState() => _MeasureSheetState();
}

class _MeasureSheetState extends State<_MeasureSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _count = TextEditingController(
    text: switch (widget.existing) {
      null => '',
      final m => '${widget.pack ? m.bases : m.units}',
    },
  );
  late final _price = TextEditingController(
    text: switch (widget.existing?.priceMinor) {
      null => '',
      final p => '${p ~/ 100}',
    },
  );

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    _price.dispose();
    super.dispose();
  }

  String get _unit => widget.unit.trim().toLowerCase();

  String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

  void _done() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final count = int.parse(_count.text.trim());
    final price = AmountField.amountFrom(_price.text);
    Navigator.of(context).pop(
      MeasureDraft(
        name: _name.text.trim(),
        units: widget.pack ? 1 : count,
        bases: widget.pack ? count : 1,
        priceMinor: price == null || price == 0 ? null : price,
      ),
    );
  }

  /// What this way does to stock and takings, as filled in so far.
  String? _note() {
    final count = int.tryParse(_count.text.trim());
    if (count == null || count < 2) return null;
    final word = Measure(
      id: 0,
      itemId: 0,
      name: _name.text.trim().isEmpty
          ? (widget.pack ? 'pack' : 'one')
          : _name.text,
      units: 1,
      bases: 1,
    ).word;
    final price = AmountField.amountFrom(_price.text);
    final whole = widget.unitPriceMinor;
    final units = unitFor(_unit, count * milli);
    if (widget.pack) {
      final first = 'Each $word bought adds $count $units to stock.';
      if (price == null || price == 0 || whole == null) return first;
      return '$first A $word sells for KES ${_plain(price)}, against '
          'KES ${_plain(whole * count)} for $count $units.';
    }
    final first = 'Each $word sold takes 1/$count of a $_unit out of stock.';
    if (price == null || price == 0) return first;
    final takings =
        '$count ${plural(word, count)} bring in KES ${_plain(price * count)} '
        'a $_unit';
    return whole == null
        ? '$first $takings.'
        : '$first $takings, against KES ${_plain(whole)} for the whole '
              '$_unit.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final pack = widget.pack;
    final editing = widget.existing != null;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pack ? 'A pack size' : 'Sell it another way',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.item} · counted in ${unitFor(_unit, 2 * milli)}',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const Key('measure-name'),
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: pack ? 'Crate' : 'Tot, 25 ml',
            ),
            validator: (t) => (t ?? '').trim().isEmpty
                ? (pack
                      ? 'Enter what the pack is, such as Crate.'
                      : 'Enter what it is, such as Tot, 25 ml.')
                : null,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: const Key('measure-count'),
                  controller: _count,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: pack
                        ? '${_capital(unitFor(_unit, 2 * milli))} in one'
                        : 'How many in a $_unit',
                  ),
                  validator: (t) {
                    final n = int.tryParse((t ?? '').trim());
                    return n == null || n < 2
                        ? 'Enter a whole number, such as ${pack ? 24 : 30}.'
                        : null;
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AmountField(
                  key: const Key('measure-price'),
                  controller: _price,
                  label: pack ? 'Sells for (optional)' : 'Sells for',
                  allowZero: pack,
                ),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: Listenable.merge([_name, _count, _price]),
            builder: (context, _) => switch (_note()) {
              null => const SizedBox.shrink(),
              final note => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: InfoNote(note, key: const Key('measure-note')),
              ),
            },
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('measure-save'),
            onPressed: _done,
            child: Text(editing ? 'Save' : 'Add'),
          ),
          if (editing)
            TextButton(
              key: const Key('measure-remove'),
              onPressed: () =>
                  Navigator.of(context).pop(const MeasureDraft.removed()),
              child: Text(
                pack ? 'Stop buying it this way' : 'Stop selling it this way',
              ),
            ),
        ],
      ),
    );
  }
}

String _capital(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
