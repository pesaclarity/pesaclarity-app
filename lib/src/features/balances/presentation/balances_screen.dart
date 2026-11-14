import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/balances_repository.dart';
import '../../../domain/ledger/balance_check.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/hero_figure_card.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../currency/application/currency_controller.dart';
import '../../income/application/income_providers.dart';
import '../application/balances_providers.dart';
import 'add_account_sheet.dart';
import 'balance_text.dart';
import 'set_balance_sheet.dart';

/// Every account in the space with what it holds now and whether its
/// messages add up. Opened from Profile and from On hand on Home.
class BalancesScreen extends ConsumerWidget {
  const BalancesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(balancesOverviewProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(BalanceText.balancesTitle),
        actions: const [AmountsEye(), SizedBox(width: 8)],
      ),
      body: AmountsHiddenScope(
        child: switch (state) {
          AsyncValue(:final value?) => _Body(value),
          AsyncValue(hasError: true) => ErrorView(
            'Balances could not load.',
            onRetry: () => ref.invalidate(balancesOverviewProvider),
          ),
          _ => const LoadingView(),
        },
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.overview);

  final BalancesOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final base = ref.watch(baseCurrencyProvider);
    final fund = ref.watch(rainyDayFundProvider).value?.balanceMinor ?? 0;
    final dayToDay = overview.dayToDay;
    final dayToDayMinor = dayToDay
        .where((a) => a.opening.currency == base)
        .fold(0, (sum, a) => sum + a.heldMinor);
    String plain(int minor) => shownMoney(context, minor);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Layout.gutter,
        8,
        Layout.gutter,
        Layout.screenBottom,
      ),
      children: [
        Text(
          BalanceText.balancesIntro,
          style: theme.textTheme.bodyLarge!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: Layout.cardGap),
        HeroFigureCard(
          key: const Key('balances-total'),
          label: BalanceText.allAccounts,
          figure: shownMoney(
            context,
            overview.totalMinor(base),
            withCurrency: true,
          ),
          caption: BalanceText.summary(
            overview.matchingCount,
            overview.needALook.length,
          ),
          showEye: false,
        ),
        if (dayToDay.isNotEmpty)
          GroupedSection(
            header: BalanceText.dayToDay.toUpperCase(),
            children: [for (final a in dayToDay) _AccountRow(a)],
          ),
        if (overview.savings.isNotEmpty)
          GroupedSection(
            header: BalanceText.savings.toUpperCase(),
            children: [for (final a in overview.savings) _AccountRow(a)],
          ),
        const SizedBox(height: Layout.cardGap),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            fund > 0
                ? BalanceText.onHandRule(
                    plain(dayToDayMinor),
                    plain(fund),
                    plain(dayToDayMinor - fund),
                  )
                : BalanceText.onHandRuleNoFund,
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('balances-check-all'),
          onPressed: () => context.push(AppRoutes.balanceCheck),
          child: const Text(BalanceText.checkAll),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('balances-add-account'),
          icon: const Icon(Icons.add),
          label: const Text(BalanceText.addAccount),
          onPressed: () => showAddAccountSheet(context),
        ),
      ],
    );
  }
}

/// `today 14:05`, `Wed 12 Nov`.
String whenLabel(DateTime at, CalendarDate today) {
  final day = CalendarDate.local(at);
  return day == today
      ? 'today ${formatTime(at)}'
      : dayHeading(day, today: today);
}

/// The initial of [name] in a soft square, like an Activity row's.
class AccountLetter extends StatelessWidget {
  const AccountLetter(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final letter = name.trim().isEmpty ? '#' : name.trim()[0].toUpperCase();
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.brandSoft,
        borderRadius: BorderRadius.circular(Layout.tagRadius),
      ),
      child: Text(
        letter,
        style: theme.textTheme.titleMedium!.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

/// The badge an account's check earns.
class BalanceBadge extends StatelessWidget {
  const BalanceBadge(this.balance, {super.key});

  final AccountBalance balance;

  @override
  Widget build(BuildContext context) {
    final check = balance.check;
    return switch (check.status) {
      BalanceStatus.matches => const Tag(
        BalanceText.matches,
        tone: Tone.success,
      ),
      BalanceStatus.off => Tag(
        BalanceText.offBy(shownMoney(context, check.latestGap!.gapMinor.abs())),
        tone: Tone.warning,
      ),
      BalanceStatus.countAgain => const Tag(BalanceText.countAgain),
      BalanceStatus.notReported => const Tag(BalanceText.notReported),
    };
  }
}

class _AccountRow extends ConsumerWidget {
  const _AccountRow(this.balance);

  final AccountBalance balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final account = balance.account;
    final check = balance.check;
    final reported = check.lastReported;
    final counted = balance.lastCorrection?.occurredAt ?? check.lastCounted;
    final detail = [
      if (reported != null)
        BalanceText.said(
          shownMoney(
            context,
            reported.balanceAfterMinor ?? reported.claimedBalanceMinor ?? 0,
            currency: balance.opening.currency,
            withCurrency: true,
          ),
          whenLabel(reported.occurredAt, today),
        )
      else if (counted != null)
        BalanceText.counted(whenLabel(counted, today)),
      if (balance.fulizaOwedMinor > 0)
        BalanceText.fulizaOwed(shownMoney(context, balance.fulizaOwedMinor)),
    ].join(' · ');
    return InkWell(
      key: Key('balance-account-${account.id}'),
      onTap: () => showAccountBalanceSheet(context, balance),
      child: Padding(
        padding: const EdgeInsets.all(Layout.cardPadding),
        child: Row(
          children: [
            AccountLetter(account.name),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(account.name, style: theme.textTheme.titleMedium),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    shownMoney(
                      context,
                      balance.heldMinor,
                      currency: balance.opening.currency,
                    ),
                    style: AppTypography.rowAmount(theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 4),
                  BalanceBadge(balance),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One account: its worth, and the ways to set it right.
Future<void> showAccountBalanceSheet(
  BuildContext context,
  AccountBalance balance,
) => showAppSheet<void>(
  context: context,
  builder: (context) => AmountsHiddenScope(child: _AccountSheet(balance)),
);

class _AccountSheet extends ConsumerWidget {
  const _AccountSheet(this.balance);

  final AccountBalance balance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = balance.opening.currency;
    String money(int minor) =>
        shownMoney(context, minor, currency: currency, withCurrency: true);
    final last = balance.lastCorrection;
    return SheetBody(
      title: balance.account.name,
      subtitle: money(balance.heldMinor),
      children: [
        if (balance.fulizaOwedMinor > 0)
          Card(
            child: Column(
              children: [
                LabelValueRow(
                  label: 'In the wallet',
                  value: money(balance.walletMinor),
                ),
                LabelValueRow(
                  label: 'Fuliza owed',
                  value: money(-balance.fulizaOwedMinor),
                ),
                LabelValueRow(
                  label: 'Worth',
                  value: money(balance.heldMinor),
                  strong: true,
                ),
              ],
            ),
          ),
        const SizedBox(height: Layout.cardGap),
        FilledButton(
          key: const Key('account-set-balance'),
          onPressed: () {
            Navigator.pop(context);
            showSetBalanceSheet(context, balance);
          },
          child: const Text(BalanceText.setBalance),
        ),
        if (balance.check.needsALook) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              context.push(AppRoutes.balanceCheck);
            },
            child: const Text(BalanceText.seeTheGap),
          ),
        ],
        if (last != null) ...[
          const SizedBox(height: 8),
          TextButton(
            key: const Key('account-undo-correction'),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(context);
              await ref
                  .read(balancesRepositoryProvider)
                  .undoCorrection(last.id);
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  const SnackBar(content: Text(BalanceText.correctionUndone)),
                );
            },
            child: const Text(BalanceText.undoCorrection),
          ),
        ],
      ],
    );
  }
}
