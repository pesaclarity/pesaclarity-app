import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/balances_repository.dart';
import '../../../domain/enums.dart';
import '../../../domain/ledger/balance_check.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/time/calendar.dart';
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
import '../application/balances_providers.dart';
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
    String when(LedgerEntry e) =>
        '${dayHeading(e.date, today: today)} ${formatTime(e.occurredAt)}';
    final fromBalance =
        gap.from.balanceAfterMinor ?? gap.from.claimedBalanceMinor ?? 0;
    final changed = gap.expectedMinor - fromBalance;
    final fix = gap.hints.first.fix;
    final flagged = {for (final h in gap.hints) ...h.entries.map((e) => e.id)};

    Future<void> act(Future<void> Function() action) async {
      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      await action();
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text(BalanceText.fixed)));
    }

    return SheetBody(
      title: '$name gap',
      children: [
        Card(
          child: Column(
            children: [
              if (!identical(gap.from, gap.to)) ...[
                LabelValueRow(
                  label: BalanceText.saidAt(name, when(gap.from)),
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
                label: BalanceText.saidAt(name, when(gap.to)),
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
        if (gap.between.isNotEmpty) ...[
          const SectionLabel(
            'IN THIS GAP',
            padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
          ),
          Card(
            child: Column(
              children: [
                for (final e in gap.between)
                  ListTile(
                    tileColor: flagged.contains(e.id)
                        ? colors.warningSoft
                        : null,
                    leading: AccountLetter(entryName(e)),
                    title: Text(entryName(e)),
                    subtitle: Text(
                      '${dayHeading(e.date, today: today)} · ${_source(e.source)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Text(
                      money(e.signedMinor),
                      style: AppTypography.rowAmount(
                        theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (fix != null) ...[
          FilledButton(
            key: const Key('gap-fix'),
            onPressed: () => act(() => applyGapFix(ref, fix)),
            child: Text(BalanceText.fixLabel(fix, accountName: name)),
          ),
          const SizedBox(height: 8),
        ],
        OutlinedButton(
          key: const Key('gap-correction'),
          onPressed: () => act(() => correctGap(ref, gap, currency)),
          child: const Text(BalanceText.addCorrectionInstead),
        ),
      ],
    );
  }
}
