import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/categoriser/suggester.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/ledger/activity_lines.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/ledger/ledger_role.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../../categoriser/application/categoriser_providers.dart';
import '../../categoriser/presentation/category_suggestion_sheet.dart';
import '../../export/presentation/export_sheet.dart';
import '../../payees/application/tag_filter.dart';
import '../../payees/presentation/transaction_sheet.dart';
import '../application/activity_providers.dart';
import 'name_payee_sheet.dart';

String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

/// Activity tab: where did my money go?
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({
    this.initialFilter = const ActivityFilter(),
    super.key,
  });

  /// The filter to open with, such as the one behind a number on Home.
  final ActivityFilter initialFilter;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  late var _filter = widget.initialFilter;
  final _search = TextEditingController();
  var _pages = 1;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Applies [change] to the current filter, so taps in quick succession
  /// each build on the last.
  void _update(ActivityFilter Function(ActivityFilter) change) =>
      setState(() => _filter = change(_filter));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.nairobi(ref.watch(clockProvider)());
    final from = _filter.from ?? today.addDays(-activityPageDays * _pages);
    final loaded = ref.watch(activityEntriesProvider(from));
    final entries = loaded.value ?? const <LedgerEntry>[];
    final accounts = ref.watch(activityAccountsProvider).value ?? const {};
    final categories = ref.watch(activityCategoriesProvider).value ?? const {};
    final suggester = ref.watch(categorySuggesterProvider);

    String? categoryName(LedgerEntry e) =>
        e.categoryId == null ? null : categories[e.categoryId]?.name;

    final inWindow = _filter.copyWith(from: () => _filter.from ?? from);
    final tagId = ref.watch(activityTagFilterProvider);
    final shown = entries.where(
      (e) =>
          matchesTagFilter(e, tagId) &&
          inWindow.matches(
            e,
            labels: [categoryName(e), accounts[e.accountId]?.name],
          ),
    );
    final days = buildActivityFeed(shown, all: entries);
    final week = weekInOut(
      entries.where(
        (e) => _filter.accountId == null || e.accountId == _filter.accountId,
      ),
      today: today,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    identifier: SemanticIds.titleActivity,
                    child: Text(
                      'Activity',
                      style: theme.textTheme.headlineLarge,
                    ),
                  ),
                ),
                const ActivityExportButton(),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _search,
              onChanged: (q) => _update((f) => f.copyWith(query: q)),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search payee, amount, note',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _filter.query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _update((f) => f.copyWith(query: ''));
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            _Filters(filter: _filter, accounts: accounts, onChanged: _update),
            const SizedBox(height: 16),
            _WeekCard(week),
            const SizedBox(height: 8),
            if (loaded.isLoading && !loaded.hasValue)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (days.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  entries.isEmpty
                      ? 'Transactions show here once your messages are read, '
                            'or when you add one with + on Home.'
                      : 'Nothing matches these filters.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
              )
            else
              for (final day in days) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
                  child: Text(
                    dayHeading(day.date, today: today).toUpperCase(),
                    style: theme.textTheme.labelLarge!.copyWith(
                      color: colors.textMuted,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                for (final line in day.lines)
                  _ActivityRow(
                    line: line,
                    accounts: accounts,
                    categoryName: categoryName,
                    categories: categories,
                    suggest: (e) => suggester?.suggest(e),
                    onAccept: (e, s) =>
                        confirmCategory(ref, e, s.categoryId, s),
                  ),
              ],
            if (_filter.from == null && entries.isNotEmpty) ...[
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _pages++),
                  child: Text(
                    'Show older',
                    style: TextStyle(color: colors.link),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.filter,
    required this.accounts,
    required this.onChanged,
  });

  final ActivityFilter filter;
  final Map<int, Account> accounts;
  final void Function(ActivityFilter Function(ActivityFilter)) onChanged;

  @override
  Widget build(BuildContext context) {
    final from = filter.from;
    final to = filter.to;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _Chip(
          label: 'All accounts',
          selected: filter.accountId == null,
          onTap: () => onChanged((f) => f.copyWith(accountId: () => null)),
        ),
        for (final a in accounts.values)
          _Chip(
            label: a.name,
            selected: filter.accountId == a.id,
            onTap: () => onChanged(
              (f) => f.copyWith(
                accountId: () => f.accountId == a.id ? null : a.id,
              ),
            ),
          ),
        for (final type in ActivityType.values.skip(1))
          _Chip(
            label: type.label,
            selected: filter.type == type,
            onTap: () => onChanged(
              (f) => f.copyWith(type: f.type == type ? ActivityType.all : type),
            ),
          ),
        if (filter.hasDateRange)
          InputChip(
            label: Text(
              from == null
                  ? 'Up to ${shortDate(to!)}'
                  : '${shortDate(from)} – ${to == null ? 'today' : shortDate(to)}',
            ),
            deleteButtonTooltipMessage: 'Show all dates',
            onDeleted: () =>
                onChanged((f) => f.copyWith(from: () => null, to: () => null)),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: scheme.primary,
      labelStyle: TextStyle(color: selected ? scheme.onPrimary : null),
      onSelected: (_) => onTap(),
    );
  }
}

class _WeekCard extends StatelessWidget {
  const _WeekCard(this.week);

  final WeekInOut week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final label = theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BrandTokens.cardRadius),
        side: BorderSide(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Out this week', style: label),
                  Text(
                    _plain(week.outMinor),
                    style: AppTypography.amount(
                      size: 26,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('In this week', style: label),
                Text(
                  week.inMinor > 0 ? '+${_plain(week.inMinor)}' : '0',
                  style: AppTypography.amount(
                    size: 26,
                    color: colors.successText,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.line,
    required this.accounts,
    required this.categoryName,
    required this.categories,
    required this.suggest,
    required this.onAccept,
  });

  final ActivityLine line;
  final Map<int, Account> accounts;
  final String? Function(LedgerEntry) categoryName;
  final Map<int, Category> categories;
  final CategorySuggestion? Function(LedgerEntry) suggest;
  final void Function(LedgerEntry, CategorySuggestion) onAccept;

  String _account(int id) => accounts[id]?.name ?? 'Account';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted);

    return switch (line) {
      EntryLine(:final entry) when _canName(entry) => _row(
        context,
        avatar: _Avatar.text('?', colors: colors, warning: true),
        title: entry.counterpartyName ?? entry.counterpartyValue!,
        subtitle: Text(
          'Tap to name this payee',
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.warning),
        ),
        amount: _amount(context, entry.signedMinor),
        onTap: () => showNamePayeeSheet(context, entry),
      ),
      EntryLine(:final entry) when needsCategory(entry) => _uncategorised(
        context,
        entry,
      ),
      EntryLine(:final entry) => _row(
        context,
        avatar: _Avatar.text(_initials(_title(entry)), colors: colors),
        title: _title(entry),
        subtitle: Text(
          [
            _categoryLabel(entry),
            _account(entry.accountId),
            // Paid in another currency: the amount as it moved.
            if (entry.originalCurrency case final code?)
              formatMoney(Money(entry.originalAmountMinor!, currency: code)),
          ].join(' · '),
          style: muted,
        ),
        amount: _amount(context, entry.signedMinor),
        onTap: () => showTransactionSheet(context, entry.id),
      ),
      OwnTransferLine(:final outflow, :final inflow, :final shown) => _row(
        context,
        avatar: _Avatar.icon(Icons.north_east, colors: colors),
        title: outflow != null && inflow != null
            ? '${_account(outflow.accountId)} → ${_account(inflow.accountId)}'
            : outflow != null
            ? 'From ${_account(outflow.accountId)}'
            : 'To ${_account(inflow!.accountId)}',
        subtitle: Text('Own transfer · not spending', style: muted),
        amount: Text(
          _plain(shown.amountMinor),
          style: AppTypography.amount(size: 18, color: colors.textMuted),
        ),
      ),
      DailyNoiseLine() && final noise => _row(
        context,
        avatar: _Avatar.icon(Icons.layers_outlined, colors: colors),
        title: _noiseTitle(noise.group),
        subtitle: Text(
          '${noise.count} ${noise.count == 1 ? 'entry' : 'entries'} · '
          '${_account(noise.accountId)}',
          style: muted,
        ),
        amount: _amount(
          context,
          noise.direction == TransactionDirection.inflow
              ? noise.totalMinor
              : -noise.totalMinor,
        ),
      ),
    };
  }

  /// A line without a category: shows the suggestion, if any, with a
  /// one-tap accept, and opens the sheet to accept or change it.
  Widget _uncategorised(BuildContext context, LedgerEntry entry) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final suggestion = suggest(entry);
    final name = suggestion == null
        ? null
        : categories[suggestion.categoryId]?.name;
    final title = _title(entry);
    return _row(
      context,
      avatar: _Avatar.text(_initials(title), colors: colors),
      title: title,
      subtitle: Text(
        name == null
            ? 'Uncategorised · Tap to choose'
            : '$name? ${suggestion!.percent}%',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium!.copyWith(color: colors.link),
      ),
      amount: _amount(context, entry.signedMinor),
      trailing: name == null
          ? null
          : IconButton(
              tooltip: 'Accept $name',
              icon: Icon(Icons.check_circle_outline, color: colors.link),
              onPressed: () => onAccept(entry, suggestion!),
            ),
      onTap: () => showCategorySuggestionSheet(
        context,
        entry: entry,
        title: title,
        suggestion: name == null ? null : suggestion,
      ),
    );
  }

  String _categoryLabel(LedgerEntry entry) {
    if (roleOf(entry) == LedgerRole.awaitingPayee) return 'Not named yet';
    final name = categoryName(entry) ?? 'Uncategorised';
    if (entry.categoryIsAuto && entry.categoryId != null) {
      return '$name (Auto)';
    }
    return name;
  }

  Widget _row(
    BuildContext context, {
    required Widget avatar,
    required String title,
    required Widget subtitle,
    required Widget amount,
    Widget? trailing,
    VoidCallback? onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                subtitle,
              ],
            ),
          ),
          const SizedBox(width: 12),
          amount,
          ?trailing,
        ],
      ),
    ),
  );

  Widget _amount(BuildContext context, int signedMinor) {
    final colors = PesaColors.of(context);
    final inflow = signedMinor > 0;
    return Text(
      inflow ? '+${_plain(signedMinor)}' : _plain(signedMinor),
      style: AppTypography.amount(
        size: 18,
        color: inflow
            ? colors.successText
            : Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

/// Whether Activity should offer to name [entry]'s payee: it needs a name
/// and has a number or till to attach the name to.
bool _canName(LedgerEntry entry) =>
    needsPayeeName(entry) &&
    entry.counterpartyKind != null &&
    entry.counterpartyValue != null;

String _title(LedgerEntry entry) =>
    entry.payeeName ??
    entry.counterpartyName ??
    entry.note ??
    entry.counterpartyValue ??
    _kindLabel(entry.kind);

String _kindLabel(TransactionKind kind) => switch (kind) {
  TransactionKind.sent => 'Money sent',
  TransactionKind.received => 'Money received',
  TransactionKind.paybill => 'Paybill',
  TransactionKind.till => 'Buy Goods',
  TransactionKind.withdrawal => 'Cash withdrawal',
  TransactionKind.deposit => 'Cash deposit',
  TransactionKind.airtime => 'Airtime',
  TransactionKind.fulizaDraw => 'Fuliza',
  TransactionKind.fulizaRepayment => 'Fuliza repayment',
  TransactionKind.roundUp => 'Round-up',
  TransactionKind.charge => 'Charge',
  TransactionKind.reversal => 'Reversal',
  TransactionKind.bank => 'Bank transaction',
};

String _noiseTitle(NoiseGroup group) => switch (group) {
  NoiseGroup.fulizaDraws => 'Fuliza draws',
  NoiseGroup.fulizaRepayments => 'Fuliza repayments',
  NoiseGroup.roundUps => 'Round-ups to savings',
  NoiseGroup.charges => 'Charges',
  NoiseGroup.airtime => 'Airtime',
};

String _initials(String name) {
  final words = name
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(w[0]))
      .toList();
  if (words.isEmpty) return '#';
  if (words.length == 1) {
    final w = words.first;
    return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
  }
  return (words[0][0] + words[1][0]).toUpperCase();
}

class _Avatar extends StatelessWidget {
  const _Avatar.text(this.text, {required this.colors, this.warning = false})
    : icon = null;

  const _Avatar.icon(this.icon, {required this.colors})
    : text = null,
      warning = false;

  final String? text;
  final IconData? icon;
  final PesaColors colors;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final isTransfer = icon == Icons.north_east;
    final foreground = warning
        ? colors.warning
        : isTransfer
        ? colors.successText
        : colors.link;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isTransfer
            ? colors.success.withValues(alpha: 0.12)
            : colors.brandSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: icon != null
          ? Icon(icon, color: foreground, size: 22)
          : Text(
              text!,
              style: Theme.of(context).textTheme.labelLarge!
                  .copyWith(color: foreground),
            ),
    );
  }
}
