import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/fuliza_tracking.dart';
import '../../../domain/accounts/mpesa_family.dart';
import '../../../domain/categoriser/suggester.dart';
import '../../../domain/ledger/activity_feed.dart';
import '../../../domain/ledger/activity_lines.dart';
import '../../../domain/ledger/fuliza_debt.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/ledger/ledger_role.dart';
import '../../../domain/lending/loan_link.dart';
import '../../../domain/payees/payee_identifier.dart';
import '../../../domain/savings/savings_prompt.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/format/ledger_labels.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/beside_or_under.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/application/mpesa_lines_providers.dart';
import '../../accounts/application/pochi_ask.dart';
import '../../accounts/domain/institution.dart';
import '../../accounts/presentation/pochi_prompt_card.dart';
import '../../ask/presentation/ask_entry.dart';
import '../../ask/presentation/ask_strings.dart';
import '../../balances/application/balances_providers.dart';
import '../../balances/presentation/balance_text.dart';
import '../../balances/presentation/own_transfer_sheets.dart';
import '../../categoriser/application/categoriser_providers.dart';
import '../../categoriser/presentation/category_suggestion_sheet.dart';
import '../../currency/application/currency_controller.dart';
import '../../export/presentation/export_sheet.dart';
import '../../lending/application/lending_providers.dart';
import '../../payees/application/tag_filter.dart';
import '../../payees/presentation/payee_sheet.dart';
import '../../payees/presentation/transaction_sheet.dart';
import '../../savings/application/savings_providers.dart';
import '../../savings/presentation/savings_prompt_card.dart';
import '../../security/application/balance_visibility.dart';
import '../../settings/application/week_start_provider.dart';
import '../../sharing/application/share_providers.dart';
import '../../sharing/presentation/group_sync_widgets.dart';
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

  /// The line that confirms a savings account was added. It shows once:
  /// kept here while the screen is open, after it is marked seen.
  SavingsAddedNotice? _added;

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
    final plain = ref.watch(activityAccountsProvider).value ?? const {};
    final addedByOnly = ref.watch(addedByLinesProvider).value ?? const {};
    final waiting = ref.watch(myWaitingLinesProvider).value ?? const {};
    // "Added by Brian · you asked to change it to 540 · Waiting for
    // approval": a change of this member's that needed approval.
    final addedBy = waiting.isEmpty
        ? addedByOnly
        : {
            ...addedByOnly,
            for (final MapEntry(:key, :value) in waiting.entries)
              key: addedByOnly[key] == null
                  ? _cap(value)
                  : '${addedByOnly[key]} · $value',
          };
    final lineAccounts = ref.watch(readLineAccountsProvider);
    final hiddenLines = ref.watch(hiddenLineAccountsProvider);
    // The menu names each M-Pesa line; the rows do only where this space
    // reads more than one, and money between two lines is titled by their
    // names alone.
    final named = withLineNames(plain, lineAccounts);
    final bothLines = lineAccounts.length > 1;
    final accounts = bothLines ? named : plain;
    final transferNames = bothLines
        ? {
            for (final MapEntry(:key, :value) in plain.entries)
              key: lineAccounts[key] == null
                  ? value
                  : value.copyWith(name: lineAccounts[key]!.label),
          }
        : plain;
    final menuAccounts = {
      for (final MapEntry(:key, :value) in named.entries)
        if (!hiddenLines.contains(key)) key: value,
    };
    final categories = ref.watch(activityCategoriesProvider).value ?? const {};
    final suggester = ref.watch(categorySuggesterProvider);
    final fulizaAuto = ref.watch(fulizaAutoProvider).value ?? const {};
    final base = ref.watch(baseCurrencyProvider);
    final others = _otherCurrencies(entries, base);
    // With more than one currency, every amount shows its code.
    final code = others.isEmpty ? null : base;

    String? categoryName(LedgerEntry e) =>
        e.categoryId == null ? null : categories[e.categoryId]?.name;
    // A loan in Lent and borrowed reads as one: "Lent to Grace".
    final loans = ref.watch(loanLinksProvider).value ?? const {};
    String? loanLabel(LedgerEntry e) => switch (loans[e.id]) {
      final loan? => loanLinkLabel(loan.link, loan.person),
      null => null,
    };

    final inWindow = _filter.copyWith(from: () => _filter.from ?? from);
    final tagId = ref.watch(activityTagFilterProvider);
    // With Fuliza not tracked, its draws and repayments leave the list; the
    // week's money in and out still counts every entry, as before.
    final fulizaRows = ref.watch(fulizaTrackingProvider).value?.shown ?? true;
    final shown = entries.where(
      (e) =>
          (fulizaRows || !isFulizaKind(e.kind)) &&
          matchesTagFilter(e, tagId) &&
          inWindow.matches(
            e,
            labels: [
              categoryName(e),
              loanLabel(e),
              if (accounts[e.accountId] case final a?)
                accountTag(a.name, a.type),
            ],
          ),
    );
    final days = buildActivityFeed(shown, all: entries);
    final week = weekInOut(
      entries.where(
        (e) => _filter.accountId == null || e.accountId == _filter.accountId,
      ),
      today: today,
      journal: ref.watch(activityJournalProvider).value,
      weekStartsOn: ref.watch(weekStartsOnProvider),
    );

    final askFilter = askAboutFilter(_filter, categories, today);
    final head = <Widget>[
      if (_chosen.isEmpty)
        const TabHeader(
          'Activity',
          semanticsId: SemanticIds.titleActivity,
          actions: [ActivityExportButton(), AmountsEye()],
        )
      else
        MoveChosenBar(chosen: _chosen, onDone: () => setState(_chosen.clear)),
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
        accounts: menuAccounts,
        categories: categories,
        onChanged: _update,
      ),
      _FixedNote(
        accounts: accounts,
        onSeeThem: (id) => _update((f) => f.copyWith(accountId: () => id)),
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
        ),
    ];
    // A savings app's question under the payment it is about, and the
    // line that confirms it was added, under the same payment.
    final prompt = ref.watch(savingsPromptProvider).value;
    _added ??= ref.watch(savingsAddedNoticeProvider).value;
    // Pochi la Biashara's question is about payments that wait off the
    // records, so it is asked above them (decision 0026 item 5).
    final pochi = switch (ref.watch(pochiWaitingProvider).value) {
      final w? when !w.declined => w,
      _ => null,
    };
    final added = _added;
    // An M-Pesa family member's move waits as an own transfer while it is
    // asked about (decision 0026 item 5).
    bool asked(ActivityLine line) =>
        prompt != null &&
        switch (line) {
          EntryLine(:final entry) => entry.id == prompt.transactionId,
          OwnTransferLine(:final shown) => shown.id == prompt.transactionId,
          _ => false,
        };
    bool confirmed(ActivityLine line) =>
        added != null &&
        switch (line) {
          EntryLine(:final entry) => entry.id == added.transactionId,
          OwnTransferLine(:final outflow, :final inflow) =>
            outflow?.id == added.transactionId ||
                inflow?.id == added.transactionId,
          _ => false,
        };

    // Each day's heading, then its lines. Only the rows on screen are
    // built: months of history are thousands of rows.
    final feed = <Object>[
      ?pochi,
      if (!(loaded.isLoading && !loaded.hasValue))
        for (final day in days) ...[
          (day, null),
          for (final line in day.lines) ...[
            (day, line),
            if (asked(line)) prompt!,
            if (confirmed(line)) added!,
          ],
        ],
    ];
    Widget feedItem(Object item) => switch (item) {
      (final ActivityDay day, null) => SectionLabel(
        dayHeading(day.date, today: today),
      ),
      (_, final ActivityLine line) => _Choosable(
        id: line is EntryLine ? line.entry.id : null,
        chosen: _chosen,
        onToggle: _toggle,
        child: _ActivityRow(
          line: line,
          accounts: accounts,
          transferNames: transferNames,
          categoryName: categoryName,
          loanLabel: loanLabel,
          categories: categories,
          suggest: (e) => suggester?.suggest(e),
          onAccept: (e, s) => confirmCategory(ref, e, s.categoryId, s),
          base: base,
          code: code,
          fulizaAuto: fulizaAuto,
          asked: asked(line),
          addedBy: addedBy,
        ),
      ),
      // Outside the rows, so a long press never chooses them.
      final SavingsPrompt p => SavingsPromptCard(p),
      final PochiWaiting w => PochiPromptCard(w),
      final SavingsAddedNotice n => SavingsAddedLine(
        n,
        name: accounts[n.accountId]?.name ?? 'Savings',
      ),
      _ => const SizedBox.shrink(),
    };
    final tail = <Widget>[
      if (_filter.from == null && entries.isNotEmpty) ...[
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: () => setState(() => _pages++),
            child: const Text('Show older'),
          ),
        ),
      ],
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: AmountsHiddenScope(
          child: AskBarScope(
            enabled: askFilter != null,
            label: askFilter?.$1,
            route: askFilter?.$2 ?? AppRoutes.ask,
            builder: (context, bottomPadding) => GroupSyncRefresh(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding),
                itemCount: head.length + feed.length + tail.length,
                itemBuilder: (context, i) {
                  if (i < head.length) return head[i];
                  i -= head.length;
                  if (i < feed.length) return feedItem(feed[i]);
                  return tail[i - feed.length];
                },
              ),
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
    // Money is kept whole, code and number on one line, never shrunk.
    Widget figure(String text, Color color) =>
        FigureText(text, style: AppTypography.tileFigure(color));
    final out = _orHidden(
      context,
      code == null
          ? _plain(week.outMinor)
          : formatMoney(Money(week.outMinor, currency: code)),
    );
    final inn = week.inMinor > 0
        ? _orHidden(context, _signed(week.inMinor, code: code))
        : '0';
    final figureStyle = AppTypography.tileFigure(theme.colorScheme.onSurface);
    Widget side(String title, String value, Color color, {bool end = false}) =>
        Column(
          crossAxisAlignment: end
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(title, style: label),
            figure(value, color),
          ],
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Side by side while both numbers fit whole in half the card;
            // with large text, one under the other.
            LayoutBuilder(
              builder: (context, constraints) {
                final half = (constraints.maxWidth - Layout.cardGap) / 2;
                final fits = [out, inn].every(
                  (v) =>
                      FigureText.numberWidth(context, v, figureStyle) <= half,
                );
                final outSide = side(
                  'Out this week',
                  out,
                  theme.colorScheme.onSurface,
                );
                if (!fits) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      outSide,
                      const SizedBox(height: 8),
                      side('In this week', inn, colors.successText),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: outSide),
                    const SizedBox(width: Layout.cardGap),
                    Expanded(
                      child: side(
                        'In this week',
                        inn,
                        colors.successText,
                        end: true,
                      ),
                    ),
                  ],
                );
              },
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
    this.transferNames,
    required this.categoryName,
    required this.loanLabel,
    required this.categories,
    required this.suggest,
    required this.onAccept,
    required this.base,
    this.code,
    this.fulizaAuto = const {},
    this.asked = false,
    this.addedBy = const {},
  });

  final ActivityLine line;

  /// In a shared space, "Added by Jane" under what someone else added, by
  /// transaction id (decision 0031).
  final Map<int, String> addedBy;

  /// Whether a savings app's question shows under this row: the row is
  /// then the top of the question's card.
  final bool asked;

  /// Fuliza worked out from M-Pesa's balances, by entry id.
  final Map<int, FulizaAuto> fulizaAuto;

  /// The base currency, which totals are counted in.
  final String base;

  /// The base currency's code, when the list holds other currencies too.
  final String? code;
  final Map<int, Account> accounts;

  /// The accounts as an own transfer's title names them: an M-Pesa line by
  /// its name alone. [accounts] when not given.
  final Map<int, Account>? transferNames;
  final String? Function(LedgerEntry) categoryName;

  /// "Lent to Grace" for a transaction linked to a loan; null otherwise.
  final String? Function(LedgerEntry) loanLabel;
  final Map<int, Category> categories;
  final CategorySuggestion? Function(LedgerEntry) suggest;
  final void Function(LedgerEntry, CategorySuggestion) onAccept;

  String _account(int id) => switch (accounts[id]) {
    final a? => accountTag(
      a.name,
      a.type,
      heldOn: accounts[a.linkedAccountId]?.name,
    ),
    null => 'Account',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted);
    final drawn = _line(context, theme, colors, muted);
    final row = asked ? SavingsPromptRow(child: drawn) : drawn;
    final auto = line is EntryLine
        ? fulizaAuto[(line as EntryLine).entry.id]
        : null;
    if (auto == null) return row;
    String money(int minor) => _orHidden(
      context,
      formatMoney(Money(minor, currency: auto.entry.currency)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row,
        Padding(
          key: Key('activity-fuliza-auto-${auto.entry.id}'),
          padding: const EdgeInsetsDirectional.only(start: 54, bottom: 8),
          child: Text(
            BalanceText.fulizaAutoLine(
              auto,
              money(auto.amountMinor),
              auto.feeMinor == 0 ? '' : money(auto.feeMinor),
            ),
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _line(
    BuildContext context,
    ThemeData theme,
    PesaColors colors,
    TextStyle muted,
  ) {
    return switch (line) {
      // Money into the person's own Pochi la Biashara is their business's
      // (decision 0026): it reads as such, not as money from a person.
      EntryLine(:final entry)
          when entry.isInflow &&
              isPochiReference(accounts[entry.accountId]?.reference) =>
        _row(
          context,
          avatar: _Avatar.icon(Icons.storefront_outlined, colors: colors),
          title: 'Received into your Pochi',
          subtitle: DetailLine(
            categoryName(entry) ?? 'Business',
            _account(entry.accountId),
            style: muted,
          ),
          amount: _entryAmount(context, entry),
          onTap: () => showTransactionSheet(context, entry.id),
        ),
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
      EntryLine(:final entry) when entry.isCorrection => _row(
        context,
        avatar: _Avatar.icon(Icons.tune, colors: colors),
        title: kindLabel(entry.kind),
        subtitle: DetailLine(
          'Not income or spending',
          _account(entry.accountId),
          style: muted,
        ),
        amount: _entryAmount(context, entry),
        onTap: () => showTransactionSheet(context, entry.id),
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
      OwnTransferLine(:final shown) && final transfer => _row(
        context,
        avatar: _Avatar.icon(Icons.swap_horiz, colors: colors),
        title: transferTitle(transfer, transferNames ?? accounts),
        subtitle: OwnTransferSubtitle(transfer, accounts, style: muted),
        amount: _entryAmount(
          context,
          shown,
          transfer: true,
          arrived: transfer.outflow == null ? null : transfer.inflow,
        ),
        onTap: () => showOwnTransferSheet(context, transfer),
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
          // Fuliza is borrowed money: it comes in, but it is not income.
          borrowed: noise.group == NoiseGroup.fulizaDraws,
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
        maxLines: 2,
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
    if (loanLabel(entry) case final loan?) return loan;
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
  }) {
    final nameStyle = Theme.of(context).textTheme.titleMedium;
    final by = line is EntryLine ? addedBy[(line as EntryLine).entry.id] : null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 14),
            // The amount moves under the name at larger text, where the
            // name would otherwise break a word.
            Expanded(
              child: BesideOrUnder(
                gap: 12,
                // The subtitle may be a DetailLine, which fits itself; a
                // plain Text subtitle (such as "Uncategorised · Tap to
                // choose") must keep its widest word whole too.
                leadMinWidth: math.max(
                  RowName.widestWord(context, title, nameStyle),
                  subtitle is Text && subtitle.data != null
                      ? RowName.widestWord(
                          context,
                          subtitle.data!,
                          subtitle.style,
                        )
                      : 0,
                ),
                lead: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RowName(title, style: nameStyle),
                    subtitle,
                    if (by != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          by,
                          key: const Key('activity-added-by'),
                          style: Theme.of(context).textTheme.bodySmall!
                              .copyWith(
                                color: PesaColors.of(context).textMuted,
                              ),
                        ),
                      ),
                  ],
                ),
                end: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [amount, ?trailing],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amount(
    BuildContext context,
    int signedMinor, {
    bool borrowed = false,
  }) {
    final colors = PesaColors.of(context);
    final inflow = signedMinor > 0 && !borrowed;
    final text = _orHidden(context, _signed(signedMinor, code: code));
    return readAsAmount(
      text,
      Text(
        text,
        style: AppTypography.rowAmount(
          inflow ? colors.successText : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  /// [entry]'s amount in the currency it moved in, with the base amount
  /// under it when that differs; an own [transfer] shows no sign. A
  /// transfer whose money [arrived] in another currency shows that amount
  /// under it instead, in its own currency.
  Widget _entryAmount(
    BuildContext context,
    LedgerEntry entry, {
    bool transfer = false,
    LedgerEntry? arrived,
  }) {
    final colors = PesaColors.of(context);
    final inflow = entry.direction == TransactionDirection.inflow;
    // Borrowed money comes in, but it is not income: never green.
    final green = inflow && entry.kind != TransactionKind.fulizaDraw;
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
          : green
          ? colors.successText
          : Theme.of(context).colorScheme.onSurface,
    );
    final arrivedIn = arrived?.originalCurrency ?? arrived?.currency;
    final under = arrived != null && arrivedIn != (ownCode ?? entry.currency)
        ? '→ ${_orHidden(context, formatMoney(Money(arrived.originalAmountMinor ?? arrived.amountMinor, currency: arrivedIn!), alwaysShowMinorUnits: true))}'
        : original != null
        ? '≈ ${_orHidden(context, formatMoney(Money(entry.amountMinor, currency: entry.currency)))}'
        : ownCode != null
        ? 'Not in totals yet'
        : null;
    final mainText = readAsAmount(main, Text(main, style: style));
    if (under == null) return mainText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        mainText,
        readAsAmount(
          under,
          Text(
            under,
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: colors.textMuted),
          ),
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
          // Initials shrink to fit at larger text rather than wrap.
          : FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                text!,
                softWrap: false,
                style: Theme.of(context).textTheme.labelLarge!
                    .copyWith(color: foreground),
              ),
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
    // Screen readers say whether a row is chosen, and that a long press
    // chooses it.
    return Semantics(
      checked: choosing ? on : null,
      onLongPressHint: 'Choose',
      child: GestureDetector(
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

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
