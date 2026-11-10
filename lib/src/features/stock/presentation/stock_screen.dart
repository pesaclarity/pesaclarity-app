import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/spaces/business_setup.dart';
import '../../../domain/stock/measure.dart';
import '../../../domain/stock/stock.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../../security/application/balance_visibility.dart';
import '../../spaces/application/business_setup_providers.dart';
import '../application/stock_providers.dart';
import 'item_sheet.dart';

String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

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
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final hidden = ref.watch(balancesHiddenProvider);
    final services =
        ref.watch(businessSetupProvider).value?.sells == BusinessSells.services;
    final items = ref.watch(itemsProvider).value;
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    services ? 'Services' : 'Stock',
                    style: theme.textTheme.headlineLarge,
                  ),
                ),
                if (services)
                  TextButton(
                    key: const Key('services-hours'),
                    onPressed: () => context.push(AppRoutes.hours),
                    child: Text('Hours', style: TextStyle(color: colors.link)),
                  ),
                if (products.isNotEmpty)
                  TextButton(
                    key: const Key('count-stock'),
                    onPressed: () => context.push(AppRoutes.countStock),
                    child: Text(
                      'Count stock',
                      style: TextStyle(color: colors.link),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (items == null)
              const Center(child: CircularProgressIndicator.adaptive())
            else ...[
              if (products.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: _Tile(
                        'Stock value',
                        hidden ? maskedDigits : _plain(value),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Tile(
                        'Running low',
                        low == 1 ? '1 item' : '$low items',
                      ),
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    services
                        ? 'Add what you offer and your rates, and Sell shows '
                              'them as tiles.'
                        : 'Add what you sell, and Sell shows each item as a '
                              'tile. Stock goes down as you sell and up as '
                              'you restock.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                )
              else
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final (i, item) in shown.indexed) ...[
                        if (i > 0)
                          const Divider(height: 1, indent: 16, endIndent: 16),
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
              const SizedBox(height: 16),
              OutlinedButton(
                key: const Key('add-item'),
                onPressed: () => showItemSheet(context, servicesOnly: services),
                child: const Text('Add an item'),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('stock-sell'),
        tooltip: 'Sell',
        shape: const CircleBorder(),
        onPressed: () => context.push(AppRoutes.sell),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTypography.amount(
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small tag beside a name: Running low, Service.
class StockTag extends StatelessWidget {
  const StockTag(this.text, {this.warning = false, super.key});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: warning ? colors.warning.withValues(alpha: 0.12) : colors.border,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall!
            .copyWith(color: warning ? colors.warning : colors.textMuted),
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
        : 'Sells ${priceText(item, _plain)}';
    return ListTile(
      key: Key('item-${item.id}'),
      onTap: () => context.push(AppRoutes.item(item.id)),
      title: Row(
        children: [
          Flexible(child: Text(item.name, overflow: TextOverflow.ellipsis)),
          if (item.isLow) ...[
            const SizedBox(width: 8),
            const StockTag('Running low', warning: true),
          ],
          if (!item.isProduct) ...[
            const SizedBox(width: 8),
            const StockTag('Service'),
          ],
        ],
      ),
      subtitle: Text(
        item.isProduct
            ? '$sells · costs ${_plain(item.averageCostMinor)}'
            : sells,
      ),
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
