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
import '../../../domain/payees/payee_identifier.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/format/ledger_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/domain/institution.dart';
import '../../ask/presentation/ask_entry.dart';
import '../../ask/presentation/ask_strings.dart';
import '../../categoriser/application/categoriser_providers.dart';
import '../../categoriser/presentation/category_suggestion_sheet.dart';
import '../../currency/application/currency_controller.dart';
import '../../export/presentation/export_sheet.dart';
import '../../payees/application/tag_filter.dart';
import '../../payees/presentation/payee_sheet.dart';
import '../../payees/presentation/transaction_sheet.dart';
import '../../security/application/balance_visibility.dart';
import '../../sms/application/message_recheck.dart';
import '../application/activity_providers.dart';
import 'move_chosen.dart';

String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

/// [amount] as written, or dots while amounts are hidden.
String _orHidden(BuildContext context, String amount) =>
    AmountsHidden.of(context) ? maskedDigits : amount;

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

  /// Transactions chosen with a long press, to move to another space.
  final _chosen = <int>{};

  void _toggle(int id) => setState(
    () => _chosen.contains(id) ? _chosen.remove(id) : _chosen.add(id),
  );

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

    final askFilter = askAboutFilter(_filter, categories, today);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AmountsHiddenScope(
          child: AskBarScope(
            enabled: askFilter != null,
            label: askFilter?.$1,
            route: askFilter?.$2 ?? AppRoutes.ask,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              children: [
                if (_chosen.isEmpty)
                  const TabHeader(
                    'Activity',
                    semanticsId: SemanticIds.titleActivity,
                    actions: [ActivityExportButton(), AmountsEye()],
                  )
                else
                  MoveChosenBar(
                    chosen: _chosen,
                    onDone: () => setState(_chosen.clear),
                  ),
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
                  const LoadingView(inList: true)
                else if (days.isEmpty)
                  EmptyNote(
                    entries.isEmpty
                        ? 'Transactions show here once your messages are read, '
                              'or when you add one with +.'
                        : 'Nothing matches these filters.',
                  )
                else
                  for (final day in days) ...[
                    SectionLabel(dayHeading(day.date, today: today)),
                    for (final line in day.lines)
                      _Choosable(
                        id: line is EntryLine ? line.entry.id : null,
                        chosen: _chosen,
                        onToggle: _toggle,
                        child: _ActivityRow(
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
                      ),
                  ],
                if (_filter.from == null && entries.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: () => setState(() => _pages++),
                      child: const Text('Show older'),
                    ),
                  ),
                ],
              ],
            ),
          ),
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
    final sorted = accounts.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (accounts.length > 1)
          ChoiceMenu<int?>(
            key: const Key('activity-accounts'),
            name: 'Account',
            options: [
              (null, 'All accounts'),
              for (final a in sorted)
                (a.id, mixed ? '${a.name} · ${a.currency}' : a.name),
            ],
            value: accounts.containsKey(filter.accountId)
                ? filter.accountId
                : null,
            highlight: accounts.containsKey(filter.accountId),
            itemKey: (id) => Key('activity-account-${id ?? 'all'}'),
            onChanged: (id) =>
                onChanged((f) => f.copyWith(accountId: () => id)),
          ),
        ChoiceMenu<ActivityType>(
          key: const Key('activity-types'),
          name: 'Show',
          options: [for (final t in ActivityType.values) (t, t.label)],
          value: filter.type,
          highlight: filter.type != ActivityType.all,
          itemKey: (t) => Key('activity-type-${t.name}'),
          onChanged: (t) => onChanged((f) => f.copyWith(type: t)),
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
    // A long amount with its code shrinks to fit rather than wrapping.
    Widget figure(String text, Color color, AlignmentGeometry alignment) =>
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: Text(text, style: AppTypography.tileFigure(color)),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
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
                      figure(
                        _orHidden(
                          context,
                          code == null
                              ? _plain(week.outMinor)
                              : formatMoney(
                                  Money(week.outMinor, currency: code),
                                ),
                        ),
                        theme.colorScheme.onSurface,
                        AlignmentDirectional.centerStart,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Layout.cardGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('In this week', style: label),
                      figure(
                        week.inMinor > 0
                            ? _orHidden(
                                context,
                                _signed(week.inMinor, code: code),
                              )
                            : '0',
                        colors.successText,
                        AlignmentDirectional.centerEnd,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (code != null) ...[
              const SizedBox(height: 8),
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
        onTap: () => showPayeeSheet(
          context,
          identifier: PayeeIdentifier.stored(
            entry.counterpartyKind!,
            entry.counterpartyValue!,
          ),
          suggestedName: entry.counterpartyName,
          moneyIn: entry.isInflow,
        ),
      ),
      EntryLine(:final entry) when needsCategory(entry) => _uncategorised(
        context,
        entry,
      ),
      EntryLine(:final entry) => _row(
        context,
        avatar: _Avatar.text(_initials(_title(entry)), colors: colors),
        title: _title(entry),
        subtitle: DetailLine(
          _categoryLabel(entry),
          _account(entry.accountId),
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
        avatar: const IconBadge(Icons.layers_outlined),
        title: noiseTitle(noise.group),
        subtitle: DetailLine(
          '${noise.count} ${noise.count == 1 ? 'entry' : 'entries'}',
          _account(noise.accountId),
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
        style: theme.textTheme.bodyMedium,
      ),
      amount: _entryAmount(context, entry),
      trailing: name == null
          ? null
          : IconButton(
              tooltip: 'Accept $name',
              icon: const Icon(Icons.check_circle_outline),
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
    // Money in from someone unnamed counts once they say what it was.
    if (roleOf(entry) == LedgerRole.awaitingPayee) {
      return 'Gift, loan or repayment?';
    }
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
      _orHidden(context, _signed(signedMinor, code: code)),
      style: AppTypography.rowAmount(
        inflow ? colors.successText : Theme.of(context).colorScheme.onSurface,
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
    final main = _orHidden(
      context,
      ownCode == null
          ? _signed(signed, code: code)
          : _signed(signed, code: ownCode),
    );
    final style = AppTypography.rowAmount(
      transfer
          ? colors.textMuted
          : inflow
          ? colors.successText
          : Theme.of(context).colorScheme.onSurface,
    );
    final under = original != null
        ? '≈ ${_orHidden(context, formatMoney(Money(entry.amountMinor, currency: entry.currency)))}'
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

/// A row's initials, or an own transfer's arrow, in a square the size and
/// shape of an [IconBadge], and as neutral unless it asks for something.
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
        : Theme.of(context).colorScheme.onSurface;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: warning
            ? colors.warningSoft
            : isTransfer
            ? colors.successSoft
            : colors.border,
        borderRadius: BorderRadius.circular(12),
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
/// and account their messages show. Its one action, See them, filters to
/// that account and marks the note seen.
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
    // A success Notice's box, with a title and one button.
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        key: const Key('recheck-note'),
        padding: const EdgeInsets.all(Layout.cardPadding),
        decoration: BoxDecoration(
          color: colors.successSoft,
          borderRadius: BorderRadius.circular(Layout.panelRadius),
          border: Border.all(color: colors.success.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Amounts fixed from your messages',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(body, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: PillButton(
                key: const Key('recheck-see'),
                label: 'See them',
                onPressed: () {
                  onSeeThem(account.id);
                  unawaited(_close(ref));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row that a long press chooses, and a tap then chooses or lets go,
/// while any row is chosen. Rows without an [id] cannot be chosen.
class _Choosable extends StatelessWidget {
  const _Choosable({
    required this.id,
    required this.chosen,
    required this.onToggle,
    required this.child,
  });

  final int? id;
  final Set<int> chosen;
  final ValueChanged<int> onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final id = this.id;
    if (id == null) return child;
    final choosing = chosen.isNotEmpty;
    final on = chosen.contains(id);
    return GestureDetector(
      key: Key('activity-choose-$id'),
      behavior: HitTestBehavior.opaque,
      onLongPress: () => onToggle(id),
      onTap: choosing ? () => onToggle(id) : null,
      child: Row(
        children: [
          if (choosing)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(
                on ? Icons.check_circle : Icons.radio_button_unchecked,
                color: on
                    ? Theme.of(context).colorScheme.onSurface
                    : PesaColors.of(context).textMuted,
              ),
            ),
          Expanded(
            child: AbsorbPointer(absorbing: choosing, child: child),
          ),
        ],
      ),
    );
  }
}

/// The Ask bar's words and route for [filter], such as "Ask about Food,
/// 1 to 27 Oct", or null when nothing is filtered.
(String, String)? askAboutFilter(
  ActivityFilter filter,
  Map<int, Category> categories,
  CalendarDate today,
) {
  final category = filter.categoryId == null
      ? null
      : categories[filter.categoryId]?.name;
  final from = filter.from;
  final to = filter.to ?? (from == null ? null : today);
  final range = from == null || to == null
      ? null
      : from.yearMonth == to.yearMonth
      ? '${from.day} to ${shortDate(to)}'
      : '${shortDate(from)} to ${shortDate(to)}';
  final parts = [?category, ?range];
  if (parts.isEmpty) return null;
  return (
    AskStrings.askAbout(parts.join(', ')),
    AppRoutes.askAbout(
      categoryId: category == null ? null : filter.categoryId,
      from: from == null ? null : formatCalendarDate(from),
      to: to == null ? null : formatCalendarDate(to),
    ),
  );
}
