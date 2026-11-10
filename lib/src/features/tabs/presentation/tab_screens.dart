import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/stock_repository.dart';
import '../../../data/repositories/tabs_repository.dart';
import '../../../domain/printing/slip.dart';
import '../../../domain/printing/slips.dart';
import '../../../domain/sales/tab.dart';
import '../../../domain/stock/measure.dart';
import '../../../domain/stock/stock.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../../documents/application/document_providers.dart';
import '../../printing/application/printing_providers.dart';
import '../../printing/presentation/print_sheet.dart';
import '../../sales/presentation/pay_sheet.dart';
import '../../sales/presentation/sell_screen.dart';
import '../../spaces/application/spaces_providers.dart';
import '../../stock/application/stock_providers.dart';
import '../application/tabs_providers.dart';

String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

String _kes(int minor) => formatMoney(Money(minor));

/// `13 items · since 8:40 pm`.
String _tabLine(OpenTab t) =>
    '${itemsText(t.itemCount)} · since ${formatTime(t.openedAt)}';

/// Add [lines] to an open tab or a new one. Returns the tab's name once
/// they are on it.
Future<String?> showAddToTabSheet(
  BuildContext context, {
  required List<SaleLine> lines,
}) => showAppSheet<String>(
  context: context,
  builder: (context) => _AddToTabSheet(lines: lines),
);

class _AddToTabSheet extends ConsumerStatefulWidget {
  const _AddToTabSheet({required this.lines});

  final List<SaleLine> lines;

  @override
  ConsumerState<_AddToTabSheet> createState() => _AddToTabSheetState();
}

class _AddToTabSheetState extends ConsumerState<_AddToTabSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addTo({int? tabId, required String name}) async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    try {
      final tabs = ref.read(tabsRepositoryProvider);
      final now = ref.read(clockProvider)();
      final id = tabId ?? await tabs.start(name, at: now);
      await tabs.add(id, widget.lines, at: now);
      navigator.pop(name);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = ref.watch(openTabsProvider).value ?? const <OpenTab>[];
    final count = widget.lines.fold(0, (sum, l) => sum + l.quantityMilli);
    final total = widget.lines.fold(0, (sum, l) => sum + l.totalMinor);
    return Form(
      key: _form,
      child: SheetBody(
        title: 'Add to a tab',
        subtitle: '${itemsText((count / milli).round())} · ${_kes(total)}',
        children: [
          if (open.isNotEmpty) ...[
            Card(
              child: Column(
                children: [
                  for (final (i, t) in open.reversed.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      key: Key('tab-pick-${t.id}'),
                      title: Text(t.name),
                      subtitle: Text(_tabLine(t)),
                      trailing: Text(
                        _kes(t.totalMinor),
                        style: AppTypography.rowAmount(
                          theme.colorScheme.onSurface,
                        ),
                      ),
                      onTap: _saving
                          ? null
                          : () => _addTo(tabId: t.id, name: t.name),
                    ),
                  ],
                ],
              ),
            ),
            const SectionLabel('Or start one'),
          ],
          TextFormField(
            key: const Key('tab-new'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Table 7, or a name',
            ),
            validator: (t) => (t ?? '').trim().isEmpty
                ? 'Enter a table or a name, such as Table 7.'
                : null,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('tab-add'),
            onPressed: _saving
                ? null
                : () {
                    if (!(_form.currentState?.validate() ?? false)) return;
                    _addTo(name: _name.text.trim());
                  },
            child: const Text('Add to the tab'),
          ),
        ],
      ),
    );
  }
}

/// Every open tab: what they hold, and the way to start one.
class OpenTabsScreen extends ConsumerWidget {
  const OpenTabsScreen({super.key});

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    final navigator = Navigator.of(context);
    final name = await showAdaptiveDialog<String>(
      context: context,
      builder: (context) => const _NameDialog(),
    );
    if (name == null) return;
    final id = await ref
        .read(tabsRepositoryProvider)
        .start(name, at: ref.read(clockProvider)());
    await navigator.push(
      MaterialPageRoute<void>(builder: (_) => TabScreen(tabId: id)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final open = ref.watch(openTabsProvider).value;
    if (open == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Open tabs')),
        body: const LoadingView(),
      );
    }
    final total = open.fold(0, (sum, t) => sum + t.totalMinor);
    return Scaffold(
      appBar: AppBar(title: const Text('Open tabs')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (open.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'On open tabs',
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: colors.textMuted,
                            ),
                          ),
                          Text(
                            _kes(total),
                            key: const Key('tabs-total'),
                            style: AppTypography.tileFigure(
                              theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Tabs',
                          style: theme.textTheme.bodySmall!.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        Text(
                          '${open.length}',
                          style: AppTypography.tileFigure(
                            theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (final (i, t) in open.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      key: Key('tab-${t.id}'),
                      title: Text(t.name),
                      subtitle: Text(_tabLine(t)),
                      trailing: Text(
                        _kes(t.totalMinor),
                        style: AppTypography.rowAmount(
                          theme.colorScheme.onSurface,
                        ),
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TabScreen(tabId: t.id),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Notice(
            'A tab keeps adding rounds until it is paid. Open tabs show in '
            'Close the day, so none is missed.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            key: const Key('tabs-start'),
            onPressed: () => _start(context, ref),
            child: const Text('Start a tab'),
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog.adaptive(
    title: const Text('Start a tab'),
    content: TextField(
      key: const Key('tab-start-name'),
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Name',
        hintText: 'Table 7, or a name',
      ),
      onSubmitted: (_) => _done(),
    ),
    actions: [
      DialogAction(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      DialogAction(
        key: const Key('tab-start-save'),
        onPressed: _done,
        child: const Text('Start'),
      ),
    ],
  );
}

/// One tab: its rounds, the total, and adding, printing the bill or paying.
class TabScreen extends ConsumerWidget {
  const TabScreen({required this.tabId, super.key});

  final int tabId;

  /// `Lager`, or `Whisky, 750 ml · tot` for another way of selling it.
  static String label(
    TabLine l,
    Map<int, Item> items,
    Map<int, List<Measure>> measures,
  ) {
    final item = items[l.itemId];
    if (item == null) return l.name;
    final measure = measures[item.id]
        ?.where((m) => m.id == l.measureId)
        .firstOrNull;
    return measure == null ? item.name : '${item.name} · ${measure.word}';
  }

  /// The lines as one sale, each thing once with all of it.
  static List<SaleLine> asSale(List<TabLine> lines) {
    final merged = <(int?, int?, String), SaleLine>{};
    for (final l in lines) {
      final key = (l.itemId, l.measureId, l.name);
      final before = merged[key];
      merged[key] = SaleLine(
        itemId: l.itemId,
        measureId: l.measureId,
        name: l.name,
        quantityMilli: (before?.quantityMilli ?? 0) + l.quantityMilli,
        totalMinor: (before?.totalMinor ?? 0) + l.totalMinor,
      );
    }
    return merged.values.toList();
  }

  Future<void> _print(
    BuildContext context,
    WidgetRef ref,
    OpenTab tab,
    List<(String, int)> rows,
  ) async {
    final settings = await ref.read(documentSettingsProvider.future);
    if (!context.mounted) return;
    final now = ref.read(clockProvider)();
    Slip slip() => billSlip(
      business: settings.nameOr(ref.read(activeSpaceProvider).name),
      tab: tab.name,
      date: longDate(CalendarDate.local(now)),
      time: formatTime(now),
      lines: rows,
      currency: BaseCurrency.code,
      plain: _plain,
    );
    await showPrintSheet(
      context,
      title: 'Print the bill',
      subtitle: tab.name,
      name: 'Bill ${tab.name}',
      slip: slip,
      pdf: () => slipPdf(slip()),
    );
  }

  Future<void> _pay(
    BuildContext context,
    WidgetRef ref,
    OpenTab tab,
    List<TabLine> lines,
  ) async {
    final navigator = Navigator.of(context);
    final sale = asSale(lines);
    final saved = await showPaySheet(
      context,
      totalMinor: tab.totalMinor,
      lines: sale,
      note: tab.name,
    );
    if (saved != true) return;
    await ref
        .read(tabsRepositoryProvider)
        .close(tab.id, at: ref.read(clockProvider)());
    navigator.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final tab = ref
        .watch(openTabsProvider)
        .value
        ?.where((t) => t.id == tabId)
        .firstOrNull;
    final lines = ref.watch(tabLinesProvider(tabId)).value;
    if (tab == null || lines == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tab?.name ?? 'Tab')),
        body: const LoadingView(),
      );
    }
    final items = {
      for (final i in ref.watch(itemsProvider).value ?? const <Item>[]) i.id: i,
    };
    final measures = ref.watch(measuresProvider).value ?? const {};
    final rows = [
      for (final l in lines)
        (
          '${label(l, items, measures)} × ${quantityText(l.quantityMilli)}',
          l.totalMinor,
        ),
    ];
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    return Scaffold(
      appBar: AppBar(title: Text(tab.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Open since ${formatTime(tab.openedAt)} · '
            '${itemsText(tab.itemCount)}',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (lines.isNotEmpty)
            Card(
              child: Column(
                children: [
                  for (final (i, l) in lines.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 70,
                            child: Text(formatTime(l.at), style: muted),
                          ),
                          Expanded(
                            child: Text(
                              rows[i].$1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                          Text(
                            _plain(l.totalMinor),
                            style: AppTypography.rowAmount(
                              theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Total',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          _kes(tab.totalMinor),
                          key: const Key('tab-total'),
                          style: AppTypography.rowAmount(
                            theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('tab-add-more'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SellScreen(tab: (id: tab.id, name: tab.name)),
              ),
            ),
            child: const Text('Add to this tab'),
          ),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('tab-print'),
              onPressed: () => _print(context, ref, tab, rows),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print the bill'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('tab-pay'),
              onPressed: () => _pay(context, ref, tab, lines),
              child: Text('Pay and close · ${_kes(tab.totalMinor)}'),
            ),
          ] else ...[
            const SizedBox(height: 12),
            TextButton(
              key: const Key('tab-drop'),
              onPressed: () async {
                final navigator = Navigator.of(context);
                await ref
                    .read(tabsRepositoryProvider)
                    .close(tab.id, at: ref.read(clockProvider)());
                navigator.pop();
              },
              child: const Text('Close this tab'),
            ),
          ],
        ],
      ),
    );
  }
}
