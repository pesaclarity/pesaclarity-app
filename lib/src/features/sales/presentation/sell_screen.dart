import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../data/repositories/tabs_repository.dart';
import '../../../domain/stock/measure.dart';
import '../../../domain/stock/stock.dart';
import '../../../routing/app_shell.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../stock/application/stock_providers.dart';
import '../../tabs/application/tabs_providers.dart';
import '../../tabs/presentation/tab_screens.dart';
import 'pay_sheet.dart';

/// Sell: tiles of what the business sells, or a number pad for the amount
/// when it has no items yet; then Pay.
class SellScreen extends ConsumerWidget {
  const SellScreen({this.billed = false, this.tab, super.key});

  /// Work done for a client to pay later: Billed, with credit to start.
  final bool billed;

  /// The open tab a round goes on, instead of paying now.
  final ({int id, String name})? tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (billed) return const AmountPadScreen(billed: true);
    final items = ref.watch(itemsProvider);
    final measures = ref.watch(measuresProvider).value ?? const {};
    final held = ref.watch(heldOnTabsProvider).value ?? const {};
    return switch (items) {
      AsyncData(:final value) when value.isNotEmpty => _TilesSell(
        [
          // What is on open tabs is still on the shelf but already sold.
          for (final i in value)
            held[i.id] == null ? i : i.withStock(i.stockMilli - held[i.id]!),
        ],
        measures: measures,
        tab: tab,
        openTabs: ref.watch(openTabsProvider).value?.length ?? 0,
      ),
      AsyncData() || AsyncError() => const AmountPadScreen(),
      _ => Scaffold(
        appBar: AppBar(
          title: Text(tab == null ? 'Sell' : 'Add to ${tab!.name}'),
        ),
        body: const LoadingView(),
      ),
    };
  }
}

/// A typed amount and what it was for, from [AmountPadScreen] in pick mode.
typedef TypedAmount = ({int amountMinor, String? note});

/// A number pad for the amount of a sale. With [pick], it returns the
/// amount for a Sell line instead of going on to Pay.
class AmountPadScreen extends StatefulWidget {
  const AmountPadScreen({
    this.billed = false,
    this.pick = false,
    this.title,
    super.key,
  });

  final bool billed;
  final bool pick;

  /// What it is, such as an item whose price varies.
  final String? title;

  /// The most whole shillings a sale can be keyed in as.
  static const maxDigits = 9;

  @override
  State<AmountPadScreen> createState() => _AmountPadScreenState();
}

class _AmountPadScreenState extends State<AmountPadScreen> {
  var _digits = '';
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int get _minor => _digits.isEmpty ? 0 : int.parse(_digits) * 100;

  String get _what =>
      widget.title ?? (widget.billed ? 'Work done' : 'Other sale');

  void _press(String key) => setState(() {
    if (key == '⌫') {
      if (_digits.isNotEmpty) {
        _digits = _digits.substring(0, _digits.length - 1);
      }
      return;
    }
    final next = (_digits + key).replaceFirst(RegExp('^0+'), '');
    if (next.length <= AmountPadScreen.maxDigits) _digits = next;
  });

  Future<void> _pay() async {
    final note = _note.text.trim();
    if (widget.pick) {
      Navigator.of(context).pop<TypedAmount>((
        amountMinor: _minor,
        note: note.isEmpty ? null : note,
      ));
      return;
    }
    final saved = await showPaySheet(
      context,
      totalMinor: _minor,
      note: note.isEmpty ? null : note,
      initialWay: widget.billed ? PayWay.credit : PayWay.cash,
    );
    if (saved == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final amount = formatMoney(Money(_minor));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.pick
              ? _what
              : widget.billed
              ? 'Billed'
              : 'Sell',
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              _what,
              style: theme.textTheme.bodyLarge!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Semantics(
              liveRegion: true,
              child: Text(
                amount,
                key: const Key('sell-amount'),
                style: AppTypography.leadFigure(theme.colorScheme.onSurface),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('sell-note'),
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'What for (optional)',
              ),
            ),
            const SizedBox(height: 20),
            _Keypad(onPress: _press),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: _PayBar(
          what: _what,
          amount: amount,
          action: widget.pick ? 'Add' : 'Pay',
          onPay: _minor > 0 ? _pay : null,
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onPress});

  final ValueChanged<String> onPress;

  static const _keys = [
    '1', '2', '3', //
    '4', '5', '6',
    '7', '8', '9',
    '00', '0', '⌫',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: Layout.cardGap,
      crossAxisSpacing: Layout.cardGap,
      childAspectRatio: 1.9,
      children: [
        for (final key in _keys)
          Material(
            color: colors.border,
            borderRadius: BorderRadius.circular(Layout.panelRadius),
            child: InkWell(
              key: Key('sell-key-$key'),
              borderRadius: BorderRadius.circular(Layout.panelRadius),
              onTap: () => onPress(key),
              child: Center(
                child: key == '⌫'
                    ? Icon(
                        Icons.backspace_outlined,
                        semanticLabel: 'Delete',
                        color: theme.colorScheme.onSurface,
                      )
                    : Text(
                        key,
                        style: AppTypography.tileFigure(
                          theme.colorScheme.onSurface,
                        ),
                      ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The total where the tab bar was: the same pill, in the brand colour.
class _PayBar extends StatelessWidget {
  const _PayBar({
    required this.what,
    required this.amount,
    required this.onPay,
    this.action = 'Pay',
  });

  final String what;
  final String amount;
  final String action;
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final enabled = onPay != null;
    final fg = enabled ? scheme.onPrimary : PesaColors.of(context).textMuted;
    return Material(
      key: const Key('sell-pay'),
      color: enabled ? scheme.primary : scheme.surfaceContainerHighest,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPay,
        child: SizedBox(
          height: PillNavigationBar.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        what,
                        style: textTheme.bodySmall!.copyWith(color: fg),
                      ),
                      Text(amount, style: AppTypography.tileFigure(fg)),
                    ],
                  ),
                ),
                Text(action, style: textTheme.titleMedium!.copyWith(color: fg)),
                Icon(Icons.chevron_right, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sell with items: a tile for each, a tap adds one; Other sale types an
/// amount. The total sits where the tab bar was.
class _TilesSell extends ConsumerStatefulWidget {
  const _TilesSell(
    this.items, {
    required this.measures,
    required this.tab,
    required this.openTabs,
  });

  final List<Item> items;

  /// Other ways each item sells, by item.
  final Map<int, List<Measure>> measures;

  /// The tab this round goes on, instead of paying now.
  final ({int id, String name})? tab;

  /// How many tabs are open.
  final int openTabs;

  @override
  ConsumerState<_TilesSell> createState() => _TilesSellState();
}

class _TilesSellState extends ConsumerState<_TilesSell> {
  /// How much of each item is in the sale, by item and way of selling (null
  /// for its own unit), in thousandths.
  final _counts = <(int, int?), int>{};
  final _other = <SaleLine>[];
  final _search = TextEditingController();
  String? _group;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// The ways [item] sells besides its own unit.
  List<Measure> _ways(Item item) => [
    for (final m in widget.measures[item.id] ?? const <Measure>[])
      if (m.sells) m,
  ];

  List<SaleLine> get _lines => [
    for (final item in widget.items) ...[
      if ((_counts[(item.id, null)] ?? 0) > 0)
        SaleLine(
          itemId: item.id,
          name: item.unit == null ? item.name : '${item.name}, ${item.unit}',
          quantityMilli: _counts[(item.id, null)]!,
          totalMinor: costOf(_counts[(item.id, null)]!, item.priceMinor ?? 0),
        ),
      for (final m in _ways(item))
        if ((_counts[(item.id, m.id)] ?? 0) > 0)
          SaleLine(
            itemId: item.id,
            measureId: m.id,
            name: '${item.name} · ${m.name}',
            quantityMilli: _counts[(item.id, m.id)]!,
            totalMinor: costOf(_counts[(item.id, m.id)]!, m.priceMinor!),
          ),
    ],
    ..._other,
  ];

  /// How many of [item] are in the sale, whichever way.
  int _countOf(Item item) => _counts.entries
      .where((e) => e.key.$1 == item.id)
      .fold(0, (sum, e) => sum + e.value);

  Future<void> _tap(Item item) async {
    final ways = _ways(item);
    if (ways.isNotEmpty) {
      final picked = await showAppSheet<Map<int?, int>>(
        context: context,
        builder: (context) => _WaysSheet(
          item: item,
          ways: ways,
          measures: widget.measures[item.id] ?? const [],
          counts: {
            for (final e in _counts.entries)
              if (e.key.$1 == item.id) e.key.$2: e.value ~/ milli,
          },
        ),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _counts.removeWhere((key, _) => key.$1 == item.id);
        for (final MapEntry(:key, :value) in picked.entries) {
          if (value > 0) _counts[(item.id, key)] = value * milli;
        }
      });
      return;
    }
    if (item.priceMinor != null) {
      setState(
        () =>
            _counts[(item.id, null)] = (_counts[(item.id, null)] ?? 0) + milli,
      );
      return;
    }
    // A price that varies is typed each time.
    final typed = await Navigator.of(context).push<TypedAmount>(
      MaterialPageRoute(
        builder: (_) => AmountPadScreen(pick: true, title: item.name),
      ),
    );
    if (typed == null || !mounted) return;
    setState(
      () => _other.add(
        SaleLine(
          itemId: item.id,
          name: typed.note ?? item.name,
          quantityMilli: milli,
          totalMinor: typed.amountMinor,
        ),
      ),
    );
  }

  Future<void> _otherSale() async {
    final typed = await Navigator.of(context).push<TypedAmount>(
      MaterialPageRoute(builder: (_) => const AmountPadScreen(pick: true)),
    );
    if (typed == null || !mounted) return;
    setState(
      () => _other.add(
        SaleLine(
          name: typed.note ?? 'Other sale',
          quantityMilli: milli,
          totalMinor: typed.amountMinor,
        ),
      ),
    );
  }

  /// Puts the lines on a tab, the one this screen is for or one chosen.
  Future<void> _toTab() async {
    final navigator = Navigator.of(context);
    final lines = _lines;
    final tab = widget.tab;
    final String? name;
    if (tab != null) {
      await ref
          .read(tabsRepositoryProvider)
          .add(tab.id, lines, at: ref.read(clockProvider)());
      name = tab.name;
    } else {
      name = await showAddToTabSheet(context, lines: lines);
    }
    if (name == null || !mounted) return;
    navigator.pop();
    showNote(navigator.context, 'Added to $name.');
  }

  Future<void> _pay() async {
    final lines = _lines;
    final saved = await showPaySheet(
      context,
      totalMinor: lines.fold(0, (sum, l) => sum + l.totalMinor),
      lines: lines,
      note: lines.length == 1 ? lines.single.name : null,
    );
    if (saved == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final groups = {
      for (final i in widget.items) ?i.grouping,
      if (widget.items.any((i) => !i.isProduct)) 'Services',
    }.toList();
    final query = _search.text.trim().toLowerCase();
    final shown = [
      for (final i in widget.items)
        if ((query.isEmpty || i.name.toLowerCase().contains(query)) &&
            (_group == null ||
                i.grouping == _group ||
                (_group == 'Services' && !i.isProduct)))
          i,
    ];
    final lines = _lines;
    final total = lines.fold(0, (sum, l) => sum + l.totalMinor);
    final count = lines.length;

    final tab = widget.tab;
    return Scaffold(
      appBar: AppBar(
        title: Text(tab == null ? 'Sell' : 'Add to ${tab.name}'),
        actions: [
          if (tab == null && widget.openTabs > 0) ...[
            PillButton(
              key: const Key('sell-open-tabs'),
              label: 'Open tabs · ${widget.openTabs}',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const OpenTabsScreen()),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            TextField(
              key: const Key('sell-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Search what you sell',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            if (groups.length > 1) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ChoiceMenu<String?>(
                  key: const Key('sell-groups'),
                  name: 'Group',
                  options: [(null, 'All'), for (final g in groups) (g, g)],
                  value: groups.contains(_group) ? _group : null,
                  highlight: groups.contains(_group),
                  itemKey: (g) => Key('sell-group-${g ?? 'all'}'),
                  onChanged: (g) => setState(() => _group = g),
                ),
              ),
            ] else if (groups.isNotEmpty) ...[
              const SizedBox(height: 12),
              // All, or the one group; the empty name stands for All.
              AdaptiveSegmented<String>(
                key: const Key('sell-group'),
                name: 'Group',
                segments: [('', 'All'), (groups.single, groups.single)],
                selected: _group ?? '',
                // The same keys as the menu's choices.
                segmentKey: (g) => Key('sell-group-${g.isEmpty ? 'all' : g}'),
                onChanged: (g) => setState(() => _group = g.isEmpty ? null : g),
              ),
            ],
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: Layout.cardGap,
              crossAxisSpacing: Layout.cardGap,
              childAspectRatio: 1.45,
              children: [
                for (final item in shown)
                  _Tile(
                    item: item,
                    ways: _ways(item),
                    measures: widget.measures[item.id] ?? const [],
                    count: _countOf(item),
                    onTap: () => _tap(item),
                  ),
                _OtherTile(onTap: _otherSale),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 20),
        child: tab != null
            ? _PayBar(
                what: count == 1 ? '1 item' : '$count items',
                amount: formatMoney(Money(total)),
                action: 'Add',
                onPay: total > 0 ? _toTab : null,
              )
            : Row(
                children: [
                  SizedBox(
                    height: PillNavigationBar.height,
                    child: OutlinedButton(
                      key: const Key('sell-add-to-tab'),
                      style: OutlinedButton.styleFrom(
                        shape: const StadiumBorder(),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      onPressed: total > 0 ? _toTab : null,
                      child: const Text('Add to a tab'),
                    ),
                  ),
                  const SizedBox(width: Layout.cardGap),
                  Expanded(
                    child: _PayBar(
                      what: count == 1 ? '1 item' : '$count items',
                      amount: formatMoney(Money(total)),
                      onPay: total > 0 ? _pay : null,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

String _plainMoney(int minor) => formatMoney(Money(minor), withCurrency: false);

class _Tile extends StatelessWidget {
  const _Tile({
    required this.item,
    required this.ways,
    required this.measures,
    required this.count,
    required this.onTap,
  });

  final Item item;

  /// Other ways it sells, such as a tot.
  final List<Measure> ways;

  /// Every other way it is sold or bought, for how its stock reads.
  final List<Measure> measures;

  /// How much is in the sale, in thousandths.
  final int count;
  final VoidCallback onTap;

  /// `From 150` when a smaller way sells for less, else its own price.
  String _price() {
    final cheapest = [for (final w in ways) w.priceMinor!]
        .fold<int?>(null, (low, p) => low == null || p < low ? p : low);
    final own = item.priceMinor;
    if (cheapest != null && (own == null || cheapest < own)) {
      return 'From ${_plainMoney(cheapest)}';
    }
    return priceText(item, _plainMoney);
  }

  String _stock() =>
      stockInMeasures(item.stockMilli, unit: item.unit, measures: measures) ??
      stockText(item);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final picked = count > 0;
    return Card(
      key: Key('tile-${item.id}'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Layout.panelRadius),
        side: BorderSide(
          color: picked ? theme.colorScheme.primary : colors.border,
          width: picked ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(_price(), style: theme.textTheme.titleSmall),
                  const Spacer(),
                  if (!item.isProduct)
                    const Tag('Service')
                  else if (item.isLow)
                    Tag(_stock(), tone: Tone.warning)
                  else
                    Text(
                      _stock(),
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                ],
              ),
              if (picked)
                Positioned(
                  right: 0,
                  top: 0,
                  child: CircleAvatar(
                    radius: 13,
                    backgroundColor: theme.colorScheme.primary,
                    child: Text(
                      quantityText(count),
                      style: theme.textTheme.labelMedium!.copyWith(
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OtherTile extends StatelessWidget {
  const _OtherTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('tile-other'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Layout.panelRadius),
        side: BorderSide(color: PesaColors.of(context).border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Other sale', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text('Type an amount', style: theme.textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Choose how many of each way to sell [item]: tots, doubles or bottles.
/// Returns the count of each way, by measure (null for its own unit).
class _WaysSheet extends StatefulWidget {
  const _WaysSheet({
    required this.item,
    required this.ways,
    required this.measures,
    required this.counts,
  });

  final Item item;
  final List<Measure> ways;
  final List<Measure> measures;
  final Map<int?, int> counts;

  @override
  State<_WaysSheet> createState() => _WaysSheetState();
}

class _WaysSheetState extends State<_WaysSheet> {
  late final _counts = {...widget.counts};

  /// Each way with its name and price, smallest first.
  List<(int?, String, int)> get _rows {
    final item = widget.item;
    final own = item.priceMinor;
    final unit = item.unit ?? 'Each';
    final rows = [
      for (final w in widget.ways) (w.id, w.name, w.priceMinor!, w.size),
      if (own != null) (null, _capital(unit), own, 1.0),
    ]..sort((a, b) => a.$4.compareTo(b.$4));
    return [for (final r in rows) (r.$1, r.$2, r.$3)];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final item = widget.item;
    final stock =
        stockInMeasures(
          item.stockMilli,
          unit: item.unit,
          measures: widget.measures,
        ) ??
        stockText(item);
    final rows = _rows;
    final total = rows.fold(0, (sum, r) => sum + (_counts[r.$1] ?? 0) * r.$3);
    return SheetBody(
      key: const Key('sell-ways'),
      title: item.name,
      subtitle: stock.endsWith('left') ? stock : '$stock left',
      children: [
        Card(
          child: Column(
            children: [
              for (final (i, (id, name, price)) in rows.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: theme.textTheme.titleSmall),
                            Text(
                              formatMoney(Money(price)),
                              style: theme.textTheme.bodySmall!.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StepButton(
                        key: Key('way-fewer-${id ?? 'unit'}'),
                        icon: Icons.remove,
                        tooltip: 'One fewer',
                        onPressed: (_counts[id] ?? 0) > 0
                            ? () =>
                                  setState(() => _counts[id] = _counts[id]! - 1)
                            : null,
                      ),
                      SizedBox(
                        width: 36,
                        child: Text(
                          '${_counts[id] ?? 0}',
                          key: Key('way-count-${id ?? 'unit'}'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      StepButton(
                        key: Key('way-more-${id ?? 'unit'}'),
                        icon: Icons.add,
                        tooltip: 'One more',
                        onPressed: () => setState(
                          () => _counts[id] = (_counts[id] ?? 0) + 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('sell-ways-add'),
          onPressed: () => Navigator.of(context).pop(_counts),
          child: Text(
            total > 0 ? 'Add · ${formatMoney(Money(total))}' : 'Done',
          ),
        ),
      ],
    );
  }
}

String _capital(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
