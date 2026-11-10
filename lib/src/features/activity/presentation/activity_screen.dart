import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/categoriser/suggester.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/ledger/activity_lines.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/ledger/ledger_role.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/format/ledger_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/brand_tokens.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/domain/institution.dart';
import '../../categoriser/application/categoriser_providers.dart';
import '../../categoriser/presentation/category_suggestion_sheet.dart';
import '../../currency/application/currency_controller.dart';
import '../../export/presentation/export_sheet.dart';
import '../../payees/application/tag_filter.dart';
import '../../payees/presentation/transaction_sheet.dart';
import '../../sms/application/message_recheck.dart';
import '../application/activity_providers.dart';
import 'name_payee_sheet.dart';

String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

/// [minor] with a sign for money in, and the currency code when [code] is
/// set: lists show codes once they hold more than one currency.
String _signed(int minor, {String? code}) {
  final text = code == null
      ? _plain(minor)
      : formatMoney(Money(minor, currency: code));
  return minor > 0 ? '+$text' : text;
}

/// The currencies other than the base among [entries], in the order seen.
List<String> _otherCurrencies(Iterable<LedgerEntry> entries, String base) => {
  for (final e in entries)
    if (e.originalCurrency case final code?)
      code
    else if (e.currency != base)
      e.currency,
}.toList();

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
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final from = _filter.from ?? today.addDays(-activityPageDays * _pages);
    final loaded = ref.watch(activityEntriesProvider(from));
    final entries = loaded.value ?? const <LedgerEntry>[];
    final accounts = ref.watch(activityAccountsProvider).value ?? const {};
    final categories = ref.watch(activityCategoriesProvider).value ?? const {};
    final suggester = ref.watch(categorySuggesterProvider);
    final base = ref.watch(baseCurrencyProvider);
    final others = _otherCurrencies(entries, base);
    // With more than one currency, every amount shows its code.
    final code = others.isEmpty ? null : base;

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
            _Filters(
              filter: _filter,
              accounts: accounts,
              categories: categories,
              onChanged: _update,
            ),
            _FixedNote(
              accounts: accounts,
              onSeeThem: (id) =>
                  _update((f) => f.copyWith(accountId: () => id)),
            ),
            const SizedBox(height: 16),
            _WeekCard(week, code: code, others: others),
            const SizedBox(height: 8),
            if (loaded.isLoading && !loaded.hasValue)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator.adaptive()),
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
                    base: base,
                    code: code,
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
    required this.categories,
    required this.onChanged,
  });

  final ActivityFilter filter;
  final Map<int, Account> accounts;
  final Map<int, Category> categories;
  final void Function(ActivityFilter Function(ActivityFilter)) onChanged;

  @override
  Widget build(BuildContext context) {
    final from = filter.from;
    final to = filter.to;
    final mixed = accounts.values.map((a) => a.currency).toSet().length > 1;
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
            label: mixed ? '${a.name} · ${a.currency}' : a.name,
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
        if (filter.hasCategory)
          InputChip(
            key: const Key('activity-category'),
            label: Text(
              filter.categoryId == null
                  ? 'Uncategorised'
                  : categories[filter.categoryId]?.name ?? 'Category',
            ),
            deleteButtonTooltipMessage: 'Show all categories',
            onDeleted: () => onChanged((f) => f.withoutCategory()),
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
  const _WeekCard(this.week, {this.code, this.others = const []});

  final WeekInOut week;

  /// The base currency's code, shown when the list holds others too.
  final String? code;

  /// The other currencies in the list.
  final List<String> others;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Out this week', style: label),
                      Text(
                        code == null
                            ? _plain(week.outMinor)
                            : formatMoney(Money(week.outMinor, currency: code)),
                        style: AppTypography.amount(
                          size: code == null ? 26 : 20,
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
                      week.inMinor > 0
                          ? _signed(week.inMinor, code: code)
                          : '0',
                      style: AppTypography.amount(
                        size: code == null ? 26 : 20,
                        color: colors.successText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (code != null) ...[
              const SizedBox(height: 10),
              Text(
                'Totals are in $code, your base currency. '
                '${_list(others)} amounts count at the rate of their day.',
                key: const Key('activity-currencies-note'),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `KES`, `KES and EUR`, `KES, EUR and GBP`.
String _list(List<String> codes) => codes.length < 2
    ? codes.join()
    : '${codes.sublist(0, codes.length - 1).join(', ')} and ${codes.last}';

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.line,
    required this.accounts,
    required this.categoryName,
    required this.categories,
    required this.suggest,
    required this.onAccept,
    required this.base,
    this.code,
  });

  final ActivityLine line;

  /// The base currency, which totals are counted in.
  final String base;

  /// The base currency's code, when the list holds other currencies too.
  final String? code;
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
        amount: _entryAmount(context, entry),
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
          [_categoryLabel(entry), _account(entry.accountId)].join(' · '),
          style: muted,
        ),
        amount: _entryAmount(context, entry),
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
        amount: _entryAmount(context, shown, transfer: true),
      ),
      DailyNoiseLine() && final noise => _row(
        context,
        avatar: _Avatar.icon(Icons.layers_outlined, colors: colors),
        title: noiseTitle(noise.group),
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
      amount: _entryAmount(context, entry),
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
      _signed(signedMinor, code: code),
      style: AppTypography.amount(
        size: 18,
        color: inflow
            ? colors.successText
            : Theme.of(context).colorScheme.onSurface,
      ),
    );
  }

  /// [entry]'s amount in the currency it moved in, with the base amount
  /// under it when that differs; an own [transfer] shows no sign.
  Widget _entryAmount(
    BuildContext context,
    LedgerEntry entry, {
    bool transfer = false,
  }) {
    final colors = PesaColors.of(context);
    final inflow = entry.direction == TransactionDirection.inflow;
    final original = entry.originalCurrency;
    // Converted into the base, or left in its own currency for want of a rate.
    final ownCode =
        original ?? (entry.currency != base ? entry.currency : null);
    final ownMinor = original == null
        ? entry.amountMinor
        : entry.originalAmountMinor!;
    final signed = transfer || inflow ? ownMinor : -ownMinor;
    final main = ownCode == null
        ? _signed(signed, code: code)
        : _signed(signed, code: ownCode);
    final style = AppTypography.amount(
      size: 18,
      color: transfer
          ? colors.textMuted
          : inflow
          ? colors.successText
          : Theme.of(context).colorScheme.onSurface,
    );
    final under = original != null
        ? '≈ ${formatMoney(Money(entry.amountMinor, currency: entry.currency))}'
        : ownCode != null
        ? 'Not in totals yet'
        : null;
    if (under == null) return Text(main, style: style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(main, style: style),
        Text(
          under,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: colors.textMuted),
        ),
      ],
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
    kindLabel(entry.kind);

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

/// After messages were read again: how many amounts moved to the currency
/// and account their messages show. Closes with OK; See them filters to
/// that account.
class _FixedNote extends ConsumerWidget {
  const _FixedNote({required this.accounts, required this.onSeeThem});

  final Map<int, Account> accounts;
  final ValueChanged<int> onSeeThem;

  Future<void> _close(WidgetRef ref) async {
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(MessageRecheck.noticeKey, const {});
    ref.invalidate(recheckNoticeProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(recheckNoticeProvider).value;
    final account = notice == null ? null : accounts[notice.accountId];
    if (notice == null || account == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final institution = ref
        .watch(institutionCatalogueProvider)
        .where((i) => i.id == account.institutionId)
        .firstOrNull;
    final bank = institution?.name ?? account.name;
    final n = notice.count;
    final amounts = n == 1 ? '1 amount' : '$n amounts';
    final body = notice.currencyChanged
        ? '$amounts at $bank ${n == 1 ? 'was' : 'were'} in '
              '${notice.currency}. ${n == 1 ? 'It is' : 'They are'} now in '
              '${account.name}, counted in ${notice.currency}.'
        : '$amounts at $bank ${n == 1 ? 'is' : 'are'} now in ${account.name}.';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        key: const Key('recheck-note'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.success.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Amounts fixed from your messages',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  key: const Key('recheck-see'),
                  onPressed: () {
                    onSeeThem(account.id);
                    unawaited(_close(ref));
                  },
                  child: const Text('See them'),
                ),
                OutlinedButton(
                  key: const Key('recheck-ok'),
                  onPressed: () => _close(ref),
                  child: const Text('OK'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
