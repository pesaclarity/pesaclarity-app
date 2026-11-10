import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/database/app_database.dart' hide Tag;
import '../../../domain/spaces/business_setup.dart';
import '../../../domain/stock/measure.dart';
import '../../../domain/stock/stock.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../spaces/application/business_setup_providers.dart';
import '../application/stock_providers.dart';
import 'item_sheet.dart';

/// Stock tab: what the business sells, products and services. A services
/// business calls it Services.
class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  ItemKind? _kind;

  @override
  Widget build(BuildContext context) {
    final hidden = AmountsHidden.of(context);
    final services =
        ref.watch(businessSetupProvider).value?.sells == BusinessSells.services;
    final itemsAsync = ref.watch(itemsProvider);
    final items = itemsAsync.value;
    final shown = [
      for (final i in items ?? const <Item>[])
        if (_kind == null || i.kind == _kind) i,
    ];
    final products = [
      for (final i in items ?? const <Item>[])
        if (i.isProduct) i,
    ];
    final value = products.fold(0, (sum, i) => sum + i.valueMinor);
    final low = products.where((i) => i.isLow).length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            TabHeader(
              services ? 'Services' : 'Stock',
              semanticsId: SemanticIds.titleStock,
              actions: [
                if (services) ...[
                  PillButton(
                    key: const Key('services-hours'),
                    label: 'Hours',
                    onPressed: () => context.push(AppRoutes.hours),
                  ),
                  const SizedBox(width: 8),
                ],
                if (products.isNotEmpty) ...[
                  PillButton(
                    key: const Key('count-stock'),
                    label: 'Count stock',
                    onPressed: () => context.push(AppRoutes.countStock),
                  ),
                  const SizedBox(width: 8),
                ],
                AddButton(
                  key: const Key('add-item'),
                  tooltip: 'Add an item',
                  onPressed: () =>
                      showItemSheet(context, servicesOnly: services),
                ),
                const AmountsEye(),
              ],
            ),
            if (itemsAsync.hasError && !itemsAsync.hasValue)
              ErrorView(
                services
                    ? 'Your services could not load.'
                    : 'Your stock could not load.',
                onRetry: () => ref.invalidate(itemsProvider),
              )
            else if (items == null)
              const LoadingView(inList: true)
            else ...[
              if (products.isNotEmpty) ...[
                FigureRow(
                  children: [
                    FigureTile(
                      label: 'Stock value',
                      value: moneyOrHidden(
                        value,
                        hidden: hidden,
                        withCurrency: false,
                      ),
                    ),
                    FigureTile(
                      label: 'Running low',
                      value: low == 1 ? '1 item' : '$low items',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              if (!services && items.isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ChoiceMenu<ItemKind?>(
                    key: const Key('stock-kind'),
                    name: 'Show',
                    options: const [
                      (null, 'All'),
                      (ItemKind.product, 'Products'),
                      (ItemKind.service, 'Services'),
                    ],
                    value: _kind,
                    highlight: _kind != null,
                    itemKey: (kind) => Key('stock-kind-${kind?.name ?? 'all'}'),
                    onChanged: (kind) => setState(() => _kind = kind),
                  ),
                ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                EmptyNote(
                  services
                      ? 'Add what you offer and your rates, and Sell shows '
                            'them as tiles.'
                      : 'Add what you sell, and Sell shows each item as a '
                            'tile. Stock goes down as you sell and up as '
                            'you restock.',
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final (i, item) in shown.indexed) ...[
                        if (i > 0) const Divider(height: 1),
                        _ItemRow(
                          item,
                          measures:
                              ref.watch(measuresProvider).value?[item.id] ??
                              const [],
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow(this.item, {required this.measures});

  final Item item;

  /// Other ways it is sold or bought, for how its stock reads.
  final List<Measure> measures;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sells = item.priceMinor == null
        ? 'Price varies'
        : 'Sells ${priceText(item, (m) => shownMoney(context, m, withCurrency: false))}';
    return ListTile(
      key: Key('item-${item.id}'),
      onTap: () => context.push(AppRoutes.item(item.id)),
      title: Row(
        children: [
          Flexible(child: Text(item.name, overflow: TextOverflow.ellipsis)),
          if (item.isLow) ...[
            const SizedBox(width: 8),
            const Tag('Running low', tone: Tone.warning),
          ],
          if (!item.isProduct) ...[
            const SizedBox(width: 8),
            const Tag('Service'),
          ],
        ],
      ),
      subtitle: Text(
        item.isProduct
            ? '$sells · costs '
                  '${shownMoney(context, item.averageCostMinor, withCurrency: false)}'
            : sells,
      ),
      // A quantity, not an amount: it keeps the row title's size.
      trailing: item.isProduct
          ? Text(
              stockInMeasures(
                    item.stockMilli,
                    unit: item.unit,
                    measures: measures,
                  ) ??
                  stockText(item),
              style: theme.textTheme.titleMedium,
            )
          : null,
    );
  }
}
