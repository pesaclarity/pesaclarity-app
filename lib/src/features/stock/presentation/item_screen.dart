import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart' hide Tag;
import '../../../data/repositories/stock_repository.dart';
import '../../../domain/stock/measure.dart';
import '../../../domain/stock/stock.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../sales/presentation/records_sheets.dart';
import '../application/stock_providers.dart';
import 'measure_sheet.dart';

String _plain(BuildContext context, int minor) =>
    shownMoney(context, minor, withCurrency: false);

/// One item: stock now and how long it lasts, price, cost and profit, and
/// its history of sales, restocks and counts.
class ItemScreen extends ConsumerWidget {
  const ItemScreen({required this.itemId, super.key});

  final int itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final items = ref.watch(itemsProvider);
    final item = items.value?.where((i) => i.id == itemId).firstOrNull;
    final moves = ref.watch(itemMovesProvider(itemId)).value ?? const [];
    final pace = ref.watch(itemPaceProvider(itemId)).value ?? 0;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Item')),
        body: items.hasError && !items.hasValue
            ? ErrorView(
                'This item could not load.',
                onRetry: () => ref.invalidate(itemsProvider),
              )
            : const LoadingView(),
      );
    }
    final measures = ref.watch(measuresProvider).value?[itemId] ?? const [];
    final amount = AppTypography.rowAmount(theme.colorScheme.onSurface);
    final days = daysLeft(item, soldMilliPerDay: pace);
    final unit = item.unit;
    final per = unit == null ? 'each' : 'per $unit';
    final weekStart = today.addDays(-6).startInstant;
    final week = [
      for (final m in moves)
        if (m.kind == StockMoveKind.sold && !m.at.isBefore(weekStart)) m,
    ];
    final soldWeek = week.fold(0, (sum, m) => sum - m.quantityMilli);
    // Sold several ways, the week's takings are not one price times one
    // amount.
    final weekAmount = item.priceMinor == null || measures.any((m) => m.sells)
        ? null
        : costOf(soldWeek, item.priceMinor!);

    return Scaffold(
      appBar: AppBar(
        title: Text(item.name),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (item.isProduct)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Layout.cardPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'In stock',
                          style: theme.textTheme.bodyMedium!.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        if (item.isLow) ...[
                          const SizedBox(width: 8),
                          const Tag('Running low', tone: Tone.warning),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stockInMeasures(
                            item.stockMilli,
                            unit: unit,
                            measures: measures,
                          ) ??
                          stockText(item),
                      style: AppTypography.headlineFigure(
                        theme.colorScheme.onSurface,
                      ),
                    ),
                    if (days != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        days == 0
                            ? 'Sold out at your usual pace'
                            : days == 1
                            ? 'About 1 day left at your usual pace'
                            : 'About $days days left at your usual pace',
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    ButtonPair(
                      primary: FilledButton(
                        key: const Key('item-restock'),
                        onPressed: () =>
                            showBoughtSheet(context, itemId: item.id),
                        child: const Text('Restock'),
                      ),
                      secondary: OutlinedButton(
                        key: const Key('item-count'),
                        onPressed: () => context.push(AppRoutes.countStock),
                        child: const Text('Count'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Sells for'),
                  subtitle: Text(per),
                  trailing: Text(
                    item.priceMinor == null
                        ? 'Varies'
                        : _plain(context, item.priceMinor!),
                    style: amount,
                  ),
                ),
                for (final m in measures) ...[
                  const Divider(height: 1),
                  ListTile(
                    key: Key('item-way-${m.id}'),
                    title: Text(m.name),
                    subtitle: Text(
                      m.isPack
                          ? '${m.bases ~/ m.units} '
                                '${unitFor(unit!.toLowerCase(), 2 * milli)}'
                          : '${m.units ~/ m.bases} in a ${unit!.toLowerCase()}',
                    ),
                    trailing: Text(
                      m.priceMinor == null
                          ? 'Bought only'
                          : _plain(context, m.priceMinor!),
                      style: amount,
                    ),
                    onTap: () => _way(context, ref, item, existing: m),
                  ),
                ],
                if (item.isProduct && unit != null) ...[
                  const Divider(height: 1),
                  SellAnotherWayTile(
                    key: const Key('item-add-way'),
                    onTap: () => _way(context, ref, item),
                  ),
                ],
                if (item.isProduct) ...[
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Costs you'),
                    subtitle: const Text('Average of what you paid'),
                    trailing: Text(
                      _plain(context, item.averageCostMinor),
                      style: amount,
                    ),
                  ),
                  if (item.profitPerUnitMinor case final profit?) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: Text(
                        unit == null ? 'Profit each' : 'Profit per $unit',
                      ),
                      trailing: Text(
                        _plain(context, profit),
                        style: AppTypography.rowAmount(colors.successText),
                      ),
                    ),
                  ],
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Sold this week'),
                    subtitle: Text(
                      unit == null
                          ? quantityText(soldWeek)
                          : '${quantityText(soldWeek)} ${unitFor(unit, soldWeek)}',
                    ),
                    trailing: weekAmount == null
                        ? null
                        : Text(_plain(context, weekAmount), style: amount),
                  ),
                ],
              ],
            ),
          ),
          if (moves.isNotEmpty) ...[
            const SectionLabel('History'),
            Card(
              child: Column(
                children: [
                  for (final (i, m) in moves.take(_historyLength).indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    _MoveRow(m, item: item, today: today),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Adds a way to sell [item], or changes or stops [existing].
Future<void> _way(
  BuildContext context,
  WidgetRef ref,
  Item item, {
  Measure? existing,
}) async {
  final draft = await showMeasureSheet(
    context,
    item: item.name,
    unit: item.unit!,
    unitPriceMinor: item.priceMinor,
    existing: existing == null
        ? null
        : MeasureDraft(
            name: existing.name,
            units: existing.units,
            bases: existing.bases,
            priceMinor: existing.priceMinor,
          ),
  );
  if (draft == null) return;
  final stock = ref.read(stockRepositoryProvider);
  if (existing == null) {
    await stock.addMeasure(
      item.id,
      name: draft.name,
      units: draft.units,
      bases: draft.bases,
      priceMinor: draft.priceMinor,
    );
  } else if (draft.removed) {
    await stock.removeMeasure(existing.id);
  } else {
    await stock.updateMeasure(
      Measure(
        id: existing.id,
        itemId: item.id,
        name: draft.name,
        units: draft.units,
        bases: draft.bases,
        priceMinor: draft.priceMinor,
      ),
    );
  }
  ref.invalidate(measuresProvider);
}

/// How many moves the history shows.
const _historyLength = 30;

class _MoveRow extends StatelessWidget {
  const _MoveRow(this.m, {required this.item, required this.today});

  final StockMove m;
  final Item item;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final unit = item.unit;
    final q = quantityText(m.quantityMilli.abs());
    final amount = unit == null
        ? q
        : '$q ${unitFor(unit, m.quantityMilli.abs())}';
    final perUnit = m.quantityMilli == 0
        ? 0
        : (m.costMinor * milli / m.quantityMilli.abs()).round();
    final title = switch (m.kind) {
      StockMoveKind.opening => 'Stock at the start',
      StockMoveKind.sold => 'Sold',
      StockMoveKind.restocked =>
        'Restocked at ${_plain(context, perUnit)}'
            '${unit == null ? ' each' : ' / $unit'}',
      StockMoveKind.counted =>
        'Counted · ${switch (m.reason) {
          CountReason.spoiled => 'spoiled',
          CountReason.used => 'used',
          CountReason.lost => 'lost',
          CountReason.miscounted || null => 'miscounted',
        }}',
    };
    final up = m.quantityMilli > 0;
    return ListTile(
      title: Text(title),
      subtitle: Text(dayHeading(CalendarDate.local(m.at), today: today)),
      trailing: Text(
        '${up ? '+' : '-'}$amount',
        style: AppTypography.rowAmount(
          up ? colors.successText : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
