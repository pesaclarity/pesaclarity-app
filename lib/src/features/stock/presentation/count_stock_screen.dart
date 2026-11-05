import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../domain/stock/stock.dart';
import '../../../theme/pesa_colors.dart';
import '../../sales/presentation/pay_sheet.dart';
import '../application/stock_providers.dart';

/// Count stock: what the records say against what is really there. Each
/// difference is kept as spoiled, used, lost or miscounted.
class CountStockScreen extends ConsumerStatefulWidget {
  const CountStockScreen({super.key});

  @override
  ConsumerState<CountStockScreen> createState() => _CountStockScreenState();
}

class _CountStockScreenState extends ConsumerState<CountStockScreen> {
  final _counted = <int, TextEditingController>{};
  final _reasons = <int, CountReason>{};
  var _saving = false;

  @override
  void dispose() {
    for (final c in _counted.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(Item item) => _counted.putIfAbsent(
    item.id,
    () => TextEditingController(text: quantityText(item.stockMilli)),
  );

  int? _difference(Item item) {
    final counted = quantityFrom(_controllerFor(item).text);
    if (counted == null) return null;
    final d = counted - item.stockMilli;
    return d == 0 ? null : d;
  }

  Future<void> _save(List<Item> products) async {
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      final at = ref.read(clockProvider)();
      final repo = ref.read(stockRepositoryProvider);
      for (final item in products) {
        final d = _difference(item);
        if (d == null) continue;
        await repo.count(
          item.id,
          countedMilli: item.stockMilli + d,
          reason: _reasons[item.id] ?? _defaultReason(d),
          at: at,
        );
      }
      navigator.pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static CountReason _defaultReason(int difference) =>
      difference < 0 ? CountReason.spoiled : CountReason.miscounted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final products = [
      for (final i in ref.watch(itemsProvider).value ?? const <Item>[])
        if (i.isProduct) i,
    ];
    final changed = [
      for (final i in products)
        if (_difference(i) != null) i,
    ];

    String amount(Item item, int milliQ) {
      final unit = item.unit;
      final q = quantityText(milliQ.abs());
      return unit == null ? q : '$q ${unitFor(unit, milliQ.abs())}';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Count stock')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Type what is really there. The difference is kept as spoiled, '
            'used or lost.',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, item) in products.indexed) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  ListTile(
                    title: Text(item.name),
                    subtitle: Text(() {
                      final d = _difference(item);
                      final says = 'Records say ${stockText(item)}';
                      if (d == null) return '$says · Matches';
                      return '$says · ${amount(item, d)} '
                          '${d < 0 ? 'less' : 'more'}';
                    }()),
                    trailing: SizedBox(
                      width: 96,
                      child: TextField(
                        key: Key('count-${item.id}'),
                        controller: _controllerFor(item),
                        textAlign: TextAlign.end,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          suffixText: item.unit,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final item in changed) ...[
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.name}: ${amount(item, _difference(item)!)} '
                      '${_difference(item)! < 0 ? 'less' : 'more'}',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (reason, label) in [
                          if (_difference(item)! < 0) ...[
                            (CountReason.spoiled, 'Spoiled'),
                            (CountReason.used, 'Used'),
                            (CountReason.lost, 'Lost'),
                          ],
                          (CountReason.miscounted, 'Miscounted'),
                        ])
                          ChoiceChip(
                            key: Key('reason-${item.id}-${reason.name}'),
                            label: Text(label),
                            selected:
                                (_reasons[item.id] ??
                                    _defaultReason(_difference(item)!)) ==
                                reason,
                            onSelected: (_) =>
                                setState(() => _reasons[item.id] = reason),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    InfoNote(
                      (_reasons[item.id] ??
                                  _defaultReason(_difference(item)!)) ==
                              CountReason.miscounted
                          ? 'The records are corrected, with no cost.'
                          : 'Counts as a cost of '
                                '${formatMoney(Money(costOf(_difference(item)!.abs(), item.averageCostMinor)), withCurrency: false)}'
                                ', so profit stays right.',
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('count-save'),
            onPressed: _saving ? null : () => _save(products),
            child: const Text('Save the count'),
          ),
        ],
      ),
    );
  }
}
