import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart' show ReviewItem;
import '../../../data/repositories/balances_repository.dart';
import '../../../domain/enums.dart';
import '../../../domain/ledger/balance_check.dart';
import '../../../domain/ledger/fuliza_debt.dart';
import '../../../domain/ledger/gap_leads.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/reader/message_reading.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/format/ledger_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../review/application/review_draft.dart';
import '../../review/application/review_providers.dart';
import '../application/balances_providers.dart';
import 'add_missing_sheet.dart';
import 'balance_text.dart';
import 'balances_screen.dart';

/// Walks every account's reported balances, lists the gaps with their
/// likely causes, and fixes what one tap can fix safely.
class BalanceCheckScreen extends ConsumerWidget {
  const BalanceCheckScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(balancesOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(BalanceText.checkTitle),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: AmountsHiddenScope(
        child: switch (state) {
          AsyncValue(:final value?) => _Body(value),
          AsyncValue(hasError: true) => ErrorView(
            'The balance check could not load.',
            onRetry: () => ref.invalidate(balancesOverviewProvider),
          ),
          _ => const LoadingView(),
        },
      ),
    );
  }
}

/// The name a gap line gives [entry].
String entryName(LedgerEntry entry) =>
    entry.payeeName ??
    entry.counterpartyName ??
    entry.note ??
    kindLabel(entry.kind);

/// What one [hint] says about [gap], in plain words.
String hintDetail(
  BuildContext context,
  GapHint hint,
  BalanceGap gap, {
  required String Function(int accountId) accountName,
  required CalendarDate today,
}) {
  String money(int minor) => shownMoney(context, minor, withCurrency: true);
  String day(LedgerEntry e) => dayHeading(e.date, today: today);
  final e = hint.entries.isEmpty ? null : hint.entries.first;
  return switch (hint.cause) {
    GapCause.countedTwice =>
      '${entryName(e!)} ${money(e.amountMinor)} on ${day(e)}, '
          '${hint.entries.map((x) => _source(x.source)).toSet().length > 1 ? 'from the message and from your statement' : 'in two messages'}.',
    GapCause.wrongAccount =>
      '"${entryName(e!)}" ${money(e.amountMinor)} on ${day(e)} is under '
          '${accountName(e.accountId)}. Its amount is exactly the gap.',
    GapCause.wrongDirection =>
      '${entryName(e!)} ${money(e.amountMinor)} on ${day(e)}: the other way '
          'round would make up the gap.',
    GapCause.unpairedTransfer =>
      '${money(e!.amountMinor)} ${e.isOutflow ? 'out of' : 'into'} '
          '${accountName(e.accountId)} on ${day(e)} has no side here.',
    GapCause.fuliza =>
      'A Fuliza ${e!.kind == TransactionKind.fulizaDraw ? 'draw' : 'repayment'}'
          ' of ${money(e.amountMinor)} on ${day(e)}. M-Pesa may count it '
          'another way.',
    GapCause.missed => BalanceText.unaccountedBetween(
      money(gap.gapMinor.abs()),
      dayHeading(gap.from.date, today: today),
      dayHeading(gap.to.date, today: today),
    ),
    GapCause.doubtfulBalance =>
      'The balance ${money(gap.reportedMinor)} from a message you checked on '
          "${day(gap.to)} doesn't follow from the one before, so it is left "
          'out. If it is right, add a correction.',
  };
}

String _source(TransactionSource source) => switch (source) {
  TransactionSource.sms => BalanceText.fromMessage,
  TransactionSource.statement => BalanceText.fromStatement,
  TransactionSource.manual => BalanceText.typedIn,
};

/// The section heading for [gap] on [account].
String gapHeading(BuildContext context, BalanceGap gap, String account) {
  final amount = shownMoney(context, gap.gapMinor.abs(), withCurrency: true);
  return gap.gapMinor < 0
      ? '$account · $amount more than $account says'
      : '$account · $amount short';
}

/// Applies [fix].
Future<void> applyGapFix(WidgetRef ref, GapFix fix) {
  final repository = ref.read(balancesRepositoryProvider);
  return switch (fix) {
    RemoveCopy(:final entryId, :final keptId) => repository.removeCopy(
      entryId,
      keptId: keptId,
    ),
    MoveHere(:final entryId, :final toAccountId) => repository.moveToAccount(
      entryId,
      toAccountId,
    ),
  };
}

/// Records a correction that closes [gap], just before its later balance.
Future<void> correctGap(WidgetRef ref, BalanceGap gap, String currency) {
  final at = gap.to.occurredAt.subtract(const Duration(seconds: 1));
  return ref
      .read(balancesRepositoryProvider)
      .addGapCorrection(
        gap.accountId,
        differenceMinor: gap.gapMinor,
        at: at.isAfter(gap.from.occurredAt) || identical(gap.from, gap.to)
            ? at
            : gap.from.occurredAt,
        currency: currency,
      );
}

class _Body extends ConsumerWidget {
  const _Body(this.overview);

  final BalancesOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    String name(int id) => overview.byId(id)?.account.name ?? 'Account';
    final gaps = [
      for (final a in overview.accounts)
        for (final g in a.check.gaps.reversed) (a, g),
    ];
    final fixes = [for (final (_, g) in gaps) ?g.hints.first.fix];
    final month = today.yearMonth;
    final leaks = [
      for (final a in overview.accounts)
        if (!a.isSavings)
          (a, whereItWent(a.opening, overview.entries, a.check, month: month)),
    ].where((x) => !x.$2.isEmpty).toList();
    final right = [
      for (final a in overview.accounts)
        if (!a.check.needsALook && a.check.lastReported != null) a,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Layout.gutter,
        8,
        Layout.gutter,
        Layout.screenBottom,
      ),
      children: [
        Text(
          BalanceText.thingsToFix(gaps.length),
          key: const Key('balance-check-count'),
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          BalanceText.checkIntro,
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        if (leaks.isNotEmpty) ...[
          const SectionLabel(
            'WHERE IT WENT',
            padding: EdgeInsets.fromLTRB(4, 20, 4, 6),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Layout.cardPadding,
                4,
                Layout.cardPadding,
                4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (a, l) in leaks)
                    WhereItWentLine(
                      l,
                      currency: a.opening.currency,
                      account: a.account.name,
                    ),
                  TextButton(
                    key: const Key('balance-check-leakage'),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => context.go(AppRoutes.insights),
                    child: const Text(BalanceText.seeLeakage),
                  ),
                ],
              ),
            ),
          ),
        ],
        for (final (account, gap) in gaps) ...[
          SectionLabel(
            gapHeading(context, gap, account.account.name).toUpperCase(),
            padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
          ),
          _GapCard(gap: gap, balance: account, accountName: name, today: today),
        ],
        if (right.isNotEmpty) ...[
          const SectionLabel(
            'ALREADY RIGHT',
            padding: EdgeInsets.fromLTRB(4, 20, 4, 6),
          ),
          Card(
            child: Column(
              children: [
                for (final a in right)
                  ListTile(
                    leading: AccountLetter(a.account.name),
                    title: Text(a.account.name),
                    subtitle: const Text(BalanceText.everyMessageAgrees),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          shownMoney(context, a.heldMinor),
                          style: AppTypography.rowAmount(
                            theme.colorScheme.onSurface,
                          ),
                        ),
                        const Tag(BalanceText.matches, tone: Tone.success),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (fixes.isNotEmpty) ...[
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('balance-check-fix-all'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              for (final fix in fixes) {
                await applyGapFix(ref, fix);
              }
              messenger.showSnackBar(
                const SnackBar(content: Text(BalanceText.fixed)),
              );
            },
            child: Text(BalanceText.fixAll(fixes.length)),
          ),
        ],
      ],
    );
  }
}

class _GapCard extends ConsumerWidget {
  const _GapCard({
    required this.gap,
    required this.balance,
    required this.accountName,
    required this.today,
  });

  final BalanceGap gap;
  final AccountBalance balance;
  final String Function(int) accountName;
  final CalendarDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final hint = gap.hints.first;
    final fix = hint.fix;
    return Card(
      child: InkWell(
        key: Key('gap-${gap.accountId}-${gap.to.id}'),
        onTap: () => showGapSheet(context, gap, balance),
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBadge(Icons.priority_high),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      BalanceText.causeTitle(hint.cause),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hintDetail(
                        context,
                        hint,
                        gap,
                        accountName: accountName,
                        today: today,
                      ),
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TrailingLink(
                      fix == null
                          ? BalanceText.seeTheGap
                          : BalanceText.fixLabel(
                              fix,
                              accountName: balance.account.name,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One gap: the two balances, what happened between them, and the fixes.
Future<void> showGapSheet(
  BuildContext context,
  BalanceGap gap,
  AccountBalance balance,
) => showAppSheet<void>(
  context: context,
  builder: (context) => AmountsHiddenScope(child: GapSheet(gap, balance)),
);

class GapSheet extends ConsumerWidget {
  const GapSheet(this.gap, this.balance, {super.key});

  final BalanceGap gap;
  final AccountBalance balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final name = balance.account.name;
    final currency = balance.opening.currency;
    String money(int minor) => shownMoney(context, minor, currency: currency);
    String when(DateTime t) =>
        '${dayHeading(CalendarDate.local(t), today: today)} ${formatTime(t)}';
    final fromBalance =
        gap.from.balanceAfterMinor ?? gap.from.claimedBalanceMinor ?? 0;
    final changed = gap.expectedMinor - fromBalance;
    final overview = ref.watch(balancesOverviewProvider).value;
    final entries = overview?.entries ?? gap.between;
    final waiting = ref.watch(gapWaitingProvider(balance.account.id));
    final picture = gapPicture(balance.opening, gap, entries, waiting: waiting);
    final leaks = whereItWent(
      balance.opening,
      entries,
      balance.check,
      month: gap.to.date.yearMonth,
    );
    final flagged = {for (final h in gap.hints) ...h.entries.map((e) => e.id)};
    final inGap = {for (final e in gap.between) e.id};
    final auto = {for (final a in picture.fuliza) a.entry.id: a};

    Future<void> act(Future<void> Function() action) async {
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      await action();
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text(BalanceText.fixed)));
    }

    final leads = picture.leads;
    return SheetBody(
      title: '$name gap',
      children: [
        Card(
          child: Column(
            children: [
              if (!identical(gap.from, gap.to)) ...[
                LabelValueRow(
                  label: BalanceText.saidAt(name, when(gap.from.occurredAt)),
                  value: money(fromBalance),
                ),
                LabelValueRow(
                  label: BalanceText.inAndOut,
                  value: '${changed >= 0 ? '+' : ''}${money(changed)}',
                ),
              ],
              LabelValueRow(
                label: BalanceText.soItShouldBe,
                value: money(gap.expectedMinor),
              ),
              LabelValueRow(
                label: BalanceText.saidAt(name, when(gap.to.occurredAt)),
                value: money(gap.reportedMinor),
                strong: true,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Layout.cardPadding,
                  0,
                  Layout.cardPadding,
                  12,
                ),
                child: Row(
                  children: [
                    const Expanded(child: Text(BalanceText.notExplained)),
                    Tag(money(gap.gapMinor.abs()), tone: Tone.warning),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!leaks.isEmpty) WhereItWentLine(leaks, currency: currency),
        if (leads.isNotEmpty) ...[
          const SectionLabel(
            BalanceText.likelyTheMissingOne,
            padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
          ),
          _LeadCard(
            lead: leads.first,
            gap: gap,
            balance: balance,
            when: when,
            act: act,
            primary: true,
          ),
          if (leads.length > 1) ...[
            const SectionLabel(
              BalanceText.otherLeads,
              padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
            ),
            for (final lead in leads.skip(1))
              _LeadCard(
                lead: lead,
                gap: gap,
                balance: balance,
                when: when,
                act: act,
              ),
          ],
        ],
        if (picture.waiting.isNotEmpty) ...[
          const SectionLabel(
            BalanceText.waitingToCheck,
            padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
          ),
          Card(
            child: Column(
              children: [
                for (final w in picture.waiting)
                  ListTile(
                    key: Key('gap-waiting-${w.id}'),
                    leading: const Icon(Icons.mark_email_unread_outlined),
                    title: Text(when(w.receivedAt)),
                    subtitle: Text(
                      w.amountMinor == null
                          ? BalanceText.unreadNoAmount
                          : '${money(w.amountMinor!)} '
                                '${w.direction == TransactionDirection.inflow ? BalanceText.inWord : BalanceText.outWord}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openMessage(context, w.id),
                  ),
              ],
            ),
          ),
        ],
        if (picture.around.isNotEmpty) ...[
          SectionLabel(
            BalanceText.everythingOn(name.toUpperCase()),
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
          ),
          Card(
            child: Column(
              children: [
                for (final e in picture.around)
                  _AroundRow(
                    entry: e,
                    inGap: inGap.contains(e.id),
                    flagged: flagged.contains(e.id),
                    auto: auto[e.id],
                    today: today,
                    money: money,
                    colors: colors,
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('gap-add-missing'),
          onPressed: () {
            Navigator.pop(context);
            showAddMissingSheet(context, gap, balance);
          },
          child: const Text(BalanceText.addWhatsMissing),
        ),
        const SizedBox(height: 4),
        TextButton(
          key: const Key('gap-correction'),
          onPressed: () => act(() => correctGap(ref, gap, currency)),
          child: const Text(BalanceText.justACorrection),
        ),
      ],
    );
  }
}

/// Just before [inflow], inside [gap]: M-Pesa takes Fuliza's share
/// before the money's balance is reported.
DateTime _justBefore(LedgerEntry inflow, BalanceGap gap) {
  final at = inflow.occurredAt.subtract(const Duration(seconds: 1));
  return at.isAfter(gap.from.occurredAt) ? at : inflow.occurredAt;
}

void _openMessage(BuildContext context, int id) {
  final router = GoRouter.of(context);
  Navigator.pop(context);
  router.push(AppRoutes.reviewMessage(id));
}

/// Messages from [accountId]'s institution waiting in Messages to check,
/// with the reader's suggested amount and direction.
final gapWaitingProvider = Provider.family<List<WaitingMessage>, int>((
  ref,
  accountId,
) {
  final overview = ref.watch(balancesOverviewProvider).value;
  final institution = overview?.byId(accountId)?.account.institutionId;
  if (institution == null) return const [];
  final reader = ref.watch(messageReaderProvider).value;
  return [
    for (final item
        in ref.watch(pendingReviewProvider).value ?? const <ReviewItem>[])
      if (item.institutionId == institution)
        _waiting(item.id, item.receivedAt, reader?.read(item.body ?? '')),
  ];
});

WaitingMessage _waiting(int id, DateTime at, MessageReading? reading) {
  if (reading == null || reading.kind == MessageKind.notTransaction) {
    return WaitingMessage(id: id, receivedAt: at);
  }
  final draft = ReviewDraft.fromReading(reading);
  return WaitingMessage(
    id: id,
    receivedAt: at,
    amountMinor: draft.amountMinor,
    direction: reading.kind == MessageKind.moneyIn
        ? TransactionDirection.inflow
        : TransactionDirection.outflow,
  );
}

/// One thing that may explain the gap, with its one-tap action.
class _LeadCard extends ConsumerWidget {
  const _LeadCard({
    required this.lead,
    required this.gap,
    required this.balance,
    required this.when,
    required this.act,
    this.primary = false,
  });

  final GapLead lead;
  final BalanceGap gap;
  final AccountBalance balance;
  final String Function(DateTime) when;
  final Future<void> Function(Future<void> Function()) act;
  final bool primary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final currency = balance.opening.currency;
    String money(int minor) =>
        shownMoney(context, minor, currency: currency, withCurrency: true);
    String way(TransactionDirection? d) => d == TransactionDirection.inflow
        ? BalanceText.inWord
        : BalanceText.outWord;
    String accountName(int id) =>
        ref.read(balancesOverviewProvider).value?.byId(id)?.account.name ??
        'another account';

    final (
      IconData icon,
      String detail,
      String? label,
      VoidCallback? onTap,
    ) = switch (lead) {
      UnreadLead(:final message, :final exact) => (
        Icons.mark_email_unread_outlined,
        (exact ? BalanceText.unreadExact : BalanceText.unreadOther)(
          money(message.amountMinor!),
          way(message.direction),
          when(message.receivedAt),
        ),
        BalanceText.checkThisMessage,
        () => _openMessage(context, message.id),
      ),
      OtherAccountLead(:final entry, :final fix) => (
        Icons.swap_horiz,
        BalanceText.otherAccount(
          entryName(entry),
          money(entry.amountMinor),
          accountName(entry.accountId),
        ),
        BalanceText.moveItHere,
        () => act(() => applyGapFix(ref, fix)),
      ),
      FulizaLead(:final inflow, :final amountMinor) => (
        Icons.phone_android_outlined,
        BalanceText.wentToFuliza(money(amountMinor), entryName(inflow)),
        BalanceText.itWentToFuliza,
        () => act(
          () => ref
              .read(balancesRepositoryProvider)
              .addFulizaRepayment(
                balance.account.id,
                amountMinor: amountMinor,
                at: _justBefore(inflow, gap),
                currency: currency,
              ),
        ),
      ),
      CopyLead(:final hint) => (
        Icons.copy_all_outlined,
        BalanceText.copyOf(
          entryName(hint.entries.first),
          money(hint.entries.first.amountMinor),
        ),
        hint.fix == null ? null : BalanceText.removeTheCopy,
        hint.fix == null ? null : () => act(() => applyGapFix(ref, hint.fix!)),
      ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: primary ? null : colors.textMuted,
                    ),
                  ),
                  if (label != null) ...[
                    const SizedBox(height: 8),
                    if (primary)
                      FilledButton(
                        key: const Key('gap-lead-action'),
                        onPressed: onTap,
                        child: Text(label),
                      )
                    else
                      OutlinedButton(onPressed: onTap, child: Text(label)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One entry on the account around a gap; outside the gap it is muted.
class _AroundRow extends StatelessWidget {
  const _AroundRow({
    required this.entry,
    required this.inGap,
    required this.flagged,
    required this.auto,
    required this.today,
    required this.money,
    required this.colors,
  });

  final LedgerEntry entry;
  final bool inGap;
  final bool flagged;
  final FulizaAuto? auto;
  final CalendarDate today;
  final String Function(int) money;
  final PesaColors colors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    final a = auto;
    final detail = [
      '${formatTime(e.occurredAt)} · ${_source(e.source)}',
      if (!inGap) BalanceText.outsideTheGap,
      if (a != null)
        BalanceText.fulizaAutoLine(
          a,
          money(a.amountMinor),
          a.feeMinor == 0 ? '' : money(a.feeMinor),
        ),
    ].join('\n');
    final ink = inGap ? theme.colorScheme.onSurface : colors.textMuted;
    return ListTile(
      tileColor: flagged ? colors.warningSoft : null,
      leading: AccountLetter(entryName(e)),
      title: Text(entryName(e), style: TextStyle(color: ink)),
      subtitle: Text(detail, style: theme.textTheme.bodySmall),
      trailing: Text(money(e.signedMinor), style: AppTypography.rowAmount(ink)),
    );
  }
}

/// "This month: fees 230 · Fuliza charges 64 · not explained 307", with a
/// link to leakage in Insights.
class WhereItWentLine extends StatelessWidget {
  const WhereItWentLine(
    this.leaks, {
    required this.currency,
    this.account,
    super.key,
  });

  final MoneyLeaks leaks;
  final String currency;

  /// The account's name, when the line is one of several.
  final String? account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    String money(int minor) => shownMoney(context, minor, currency: currency);
    final line = BalanceText.whereItWent(
      account == null ? BalanceText.thisMonth : '$account this month',
      money(leaks.feesMinor),
      money(leaks.fulizaMinor),
      money(leaks.notExplainedMinor),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line,
            key: Key('where-it-went-${account ?? 'gap'}'),
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
          if (account == null)
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () {
                final router = GoRouter.of(context);
                Navigator.pop(context);
                router.go(AppRoutes.insights);
              },
              child: const Text(BalanceText.seeLeakage),
            ),
        ],
      ),
    );
  }
}
