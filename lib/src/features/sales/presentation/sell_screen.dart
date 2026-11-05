import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../domain/stock/stock.dart';
import '../../../routing/app_shell.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../../stock/application/stock_providers.dart';
import '../../stock/presentation/stock_screen.dart' show StockTag;
import 'pay_sheet.dart';

/// Sell: tiles of what the business sells, or a number pad for the amount
/// when it has no items yet; then Pay.
class SellScreen extends ConsumerWidget {
  const SellScreen({this.billed = false, super.key});

  /// Work done for a client to pay later: Billed, with credit to start.
  final bool billed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (billed) return const AmountPadScreen(billed: true);
    final items = ref.watch(itemsProvider);
    return switch (items) {
      AsyncData(:final value) when value.isNotEmpty => _TilesSell(value),
      AsyncData() || AsyncError() => const AmountPadScreen(),
      _ => const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
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
                style: AppTypography.amount(
                  size: 44,
                  color: theme.colorScheme.onSurface,
                ),
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
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.9,
      children: [
        for (final key in _keys)
          Material(
            color: colors.border.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: Key('sell-key-$key'),
              borderRadius: BorderRadius.circular(16),
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
                        style: AppTypography.amount(
                          size: 24,
                          color: theme.colorScheme.onSurface,
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
    final fg = enabled ? scheme.onPrimary : scheme.onSurfaceVariant;
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
                      Text(
                        amount,
                        style: AppTypography.amount(size: 22, color: fg),
                      ),
                    ],
                  ),
                ),
                Text(
                  action,
                  style: textTheme.titleMedium!.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
class _TilesSell extends StatefulWidget {
  const _TilesSell(this.items);

  final List<Item> items;

  @override
  State<_TilesSell> createState() => _TilesSellState();
}

class _TilesSellState extends State<_TilesSell> {
  final _counts = <int, int>{};
  final _other = <SaleLine>[];
  final _search = TextEditingController();
  String? _group;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SaleLine> get _lines => [
    for (final item in widget.items)
      if ((_counts[item.id] ?? 0) > 0)
        SaleLine(
          itemId: item.id,
          name: item.unit == null ? item.name : '${item.name}, ${item.unit}',
          quantityMilli: _counts[item.id]!,
          totalMinor: costOf(_counts[item.id]!, item.priceMinor ?? 0),
        ),
    ..._other,
  ];

  Future<void> _tap(Item item) async {
    if (item.priceMinor != null) {
      setState(() => _counts[item.id] = (_counts[item.id] ?? 0) + milli);
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

    return Scaffold(
      appBar: AppBar(title: const Text('Sell')),
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
            if (groups.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: _group == null,
                    onSelected: (_) => setState(() => _group = null),
                  ),
                  for (final g in groups)
                    ChoiceChip(
                      label: Text(g),
                      selected: _group == g,
                      onSelected: (_) => setState(() => _group = g),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: [
                for (final item in shown)
                  _Tile(
                    item: item,
                    count: _counts[item.id] ?? 0,
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
        child: _PayBar(
          what: count == 1 ? '1 item' : '$count items',
          amount: formatMoney(Money(total)),
          onPay: total > 0 ? _pay : null,
        ),
      ),
    );
  }
}

String _plainMoney(int minor) => formatMoney(Money(minor), withCurrency: false);

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.count, required this.onTap});

  final Item item;

  /// How much is in the sale, in thousandths.
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final picked = count > 0;
    return Card(
      key: Key('tile-${item.id}'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: picked ? theme.colorScheme.primary : colors.border,
          width: picked ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                  Text(
                    priceText(item, _plainMoney),
                    style: theme.textTheme.titleSmall,
                  ),
                  const Spacer(),
                  if (!item.isProduct)
                    const StockTag('Service')
                  else if (item.isLow)
                    StockTag(stockText(item), warning: true)
                  else
                    Text(
                      stockText(item),
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
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: PesaColors.of(context).border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
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
