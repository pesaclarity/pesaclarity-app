import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart' hide Tag;
import '../../../data/repositories/savings_repository.dart';
import '../../../domain/savings/savings_account.dart';
import '../../../domain/savings/savings_pockets.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/beside_or_under.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/selector_field.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../../debts/presentation/due_line.dart' show IconLine;
import '../application/savings_providers.dart';
import 'savings_pocket_sheet.dart';
import 'savings_text.dart';
import 'update_savings_balance_sheet.dart';

/// Opens the page of the savings account [accountId].
Future<void> showSavingsAccount(BuildContext context, int accountId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavingsAccountScreen(accountId: accountId),
      ),
    );

/// A savings account the app keeps, such as Chumz: the balance last typed
/// and the way to update it, what went in and came out, its goals, and the
/// money in and out, newest first.
class SavingsAccountScreen extends ConsumerWidget {
  const SavingsAccountScreen({required this.accountId, super.key});

  final int accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(savingsAccountProvider(accountId));
    final account = state.value;
    final today = CalendarDate.local(ref.watch(clockProvider)());
    return Scaffold(
      appBar: AppBar(
        title: Text(account?.name ?? SavingsText.savingsApps),
        actions: [
          Center(
            child: _SavedLabel(invested: account?.product?.invested ?? false),
          ),
          const SizedBox(width: Layout.gutter),
        ],
      ),
      body: AmountsHiddenScope(
        child: switch (state) {
          AsyncValue(hasValue: true) when account == null => const _Gone(),
          AsyncValue(hasValue: true) => _Body(account: account!, today: today),
          AsyncValue(hasError: true) => ErrorView(
            'This account could not load.',
            onRetry: () => ref.invalidate(savingsAccountProvider(accountId)),
          ),
          _ => const LoadingView(),
        },
      ),
    );
  }
}

/// "Saved", in the app bar: plain muted text, saying what kind of account
/// this is.
class _SavedLabel extends StatelessWidget {
  const _SavedLabel({this.invested = false});

  /// Money invested, such as Ziidi: "Invested".
  final bool invested;

  @override
  Widget build(BuildContext context) => Text(
    invested ? SavingsText.invested : SavingsText.saved,
    style: Theme.of(context).textTheme.bodyMedium!
        .copyWith(color: PesaColors.of(context).textMuted),
  );
}

class _Gone extends StatelessWidget {
  const _Gone();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Layout.gutter),
    child: Text(
      'This savings account was removed.',
      style: Theme.of(context).textTheme.bodyLarge,
    ),
  );
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.account, required this.today});

  final SavingsAccountSummary account;
  final CalendarDate today;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  /// How many of the money in and out, and updates, show.
  var _shown = 10;

  SavingsAccountSummary get _account => widget.account;

  Future<void> _remove() async {
    final name = _account.name;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(savingsRepositoryProvider);
    final yes = await confirmDelete(
      context,
      title: SavingsText.removeTitle(name),
      body: SavingsText.removeBody(name),
      action: SavingsText.removeAction,
    );
    if (!yes) return;
    await repository.remove(_account.accountId);
    navigator.pop();
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(SavingsText.removed(name))));
  }

  @override
  Widget build(BuildContext context) {
    final account = _account;
    final today = widget.today;
    final others = ref.watch(activityAccountsProvider).value ?? const {};
    final recent = _recent(account, today);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Layout.gutter,
        4,
        Layout.gutter,
        Layout.screenBottom,
      ),
      children: [
        _BalanceCard(account: account, today: today),
        const SizedBox(height: Layout.cardGap),
        _TotalsCard(account, today: today),
        if ((account.product?.goalsByCode ?? true) &&
            (account.pockets.isNotEmpty ||
                account.ignoredPockets.isNotEmpty)) ...[
          const SectionLabel(SavingsText.goals),
          Card(
            child: Column(
              children: [
                for (final (i, p) in [
                  ...account.pockets,
                  ...account.ignoredPockets,
                ].indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _PocketRow(pocket: p, account: account, today: today),
                ],
              ],
            ),
          ),
        ],
        const SectionLabel(SavingsText.recent),
        if (recent.isEmpty)
          const EmptyNote(SavingsText.nothingYet)
        else
          Card(
            child: Column(
              children: [
                for (final (i, item) in recent.take(_shown).indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  switch (item) {
                    final SavingsEntry e => _EntryRow(
                      entry: e,
                      account: account,
                      accounts: others,
                      today: today,
                    ),
                    final UpdateOutcome u => _UpdateRow(
                      update: u,
                      account: account,
                      today: today,
                    ),
                    _ => const SizedBox.shrink(),
                  },
                ],
              ],
            ),
          ),
        if (recent.length > _shown)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _shown += 10),
              child: const Text(SavingsText.showMore),
            ),
          ),
        const SizedBox(height: 24),
        OutlinedButton(
          key: const Key('savings-rename'),
          onPressed: () => _showRenameSheet(context, account),
          child: const Text(SavingsText.changeName),
        ),
        // An M-Pesa account, or a fund read from its own messages, is one
        // of the M-Pesa family: it is not removed from here.
        if (!(account.product?.keptOnItsOwn ?? false)) ...[
          const SizedBox(height: 8),
          TextButton(
            key: const Key('savings-remove'),
            onPressed: _remove,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(SavingsText.remove(account.name)),
          ),
        ],
      ],
    );
  }
}

/// Money in and out and each update, newest first. A balance its messages
/// print (M-Shwari's) that changed nothing is left out: the money in or
/// out beside it says it all.
List<Object> _recent(SavingsAccountSummary account, CalendarDate today) {
  final fromMessages = account.product?.balanceInMessages ?? false;
  final items = <(DateTime, Object)>[
    for (final e in account.entries) (e.at, e),
    for (final u in account.updates)
      if (!fromMessages || u.changeMinor != 0) (u.at, u),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final (_, item) in items) item];
}

/// `+50`, `−1,000`, in the account's currency, masked while amounts are
/// hidden.
String _signed(BuildContext context, int minor, String currency) {
  final text = shownMoney(context, minor, currency: currency);
  return minor > 0 ? '+$text' : text;
}

class _BalanceCard extends ConsumerWidget {
  const _BalanceCard({required this.account, required this.today});

  final SavingsAccountSummary account;
  final CalendarDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    final setAt = account.balanceSetAt;
    final name = account.product?.name ?? account.name;
    final product = account.product;
    if (product != null && product.keptOnItsOwn) {
      return _MemberBalanceCard(account: account, today: today);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Layout.heroPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              SavingsText.balance,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            FigureText(
              shownMoney(
                context,
                account.balanceMinor,
                currency: account.currency,
                withCurrency: true,
              ),
              style: AppTypography.headlineFigure(theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(SavingsText.heldBy(account.product), style: muted),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: Layout.cardGap,
              runSpacing: 8,
              children: [
                Text(
                  setAt == null
                      ? SavingsText.fromPayments
                      : SavingsText.setByYou(
                          dayLabel(
                            CalendarDate.local(setAt),
                            thisYear: today.year,
                          ),
                        ),
                  style: theme.textTheme.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                PillButton(
                  key: const Key('savings-update-balance'),
                  label: SavingsText.updateBalance,
                  onPressed: account.pockets.isEmpty
                      ? null
                      : () => showUpdateSavingsBalanceSheet(context, account),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(SavingsText.noInterestSms(name), style: muted),
          ],
        ),
      ),
    );
  }
}

/// The balance of an account kept from its messages, such as Ziidi or
/// M-Shwari (decision 0026): its value or balance, what it earned this
/// month, and, where no message prints its balance, the way to type it.
class _MemberBalanceCard extends StatelessWidget {
  const _MemberBalanceCard({required this.account, required this.today});

  final SavingsAccountSummary account;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final product = account.product!;
    final setAt = account.balanceSetAt;
    final earned = account.updates
        .where((u) {
          final day = CalendarDate.local(u.at);
          return day.year == today.year && day.month == today.month;
        })
        .fold(0, (sum, u) => sum + u.interestMinor);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Layout.heroPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              product.invested ? SavingsText.value : SavingsText.balance,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            FigureText(
              shownMoney(
                context,
                account.balanceMinor,
                currency: account.currency,
                withCurrency: true,
              ),
              style: AppTypography.headlineFigure(theme.colorScheme.onSurface),
            ),
            if (earned > 0) ...[
              const SizedBox(height: 10),
              IconLine(
                icon: Icons.trending_up,
                iconSize: 18,
                iconColor: colors.successText,
                text: TextSpan(
                  text: SavingsText.earnedThisMonth(
                    shownMoney(
                      context,
                      earned,
                      currency: account.currency,
                      withCurrency: false,
                    ),
                    invested: product.invested,
                  ),
                ),
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.successText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            // No message prints its value: the person types it.
            if (!product.balanceInMessages) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Layout.cardGap,
                runSpacing: 8,
                children: [
                  Text(
                    setAt == null
                        ? SavingsText.fromPayments
                        : SavingsText.setByYou(
                            dayLabel(
                              CalendarDate.local(setAt),
                              thisYear: today.year,
                            ),
                          ),
                    style: theme.textTheme.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  PillButton(
                    key: const Key('savings-update-balance'),
                    label: SavingsText.updateBalance,
                    onPressed: account.pockets.isEmpty
                        ? null
                        : () => showUpdateSavingsBalanceSheet(context, account),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard(this.account, {required this.today});

  final SavingsAccountSummary account;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final currency = account.currency;
    String plain(int minor) =>
        shownMoney(context, minor, currency: currency, withCurrency: false);
    final product = account.product;
    if (product != null && product.keptOnItsOwn) {
      return _MemberTotals(account: account, today: today);
    }
    final rows = [
      _Fact(SavingsText.putIn, plain(account.putInMinor)),
      _Fact(SavingsText.takenOut, plain(account.takenOutMinor)),
      if (account.balanceSetAt != null)
        _Fact(
          SavingsText.interestSoFar,
          _signed(context, account.interestMinor, currency),
        ),
      // So the lines add up to the balance.
      if (account.wasThereBeforeMinor != 0)
        _Fact(
          SavingsText.wasThereBefore,
          _signed(context, account.wasThereBeforeMinor, currency),
        ),
      if (account.otherChangesMinor != 0)
        _Fact(
          SavingsText.otherChanges,
          _signed(context, account.otherChangesMinor, currency),
        ),
    ];
    return Card(
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1),
            row,
          ],
        ],
      ),
    );
  }
}

/// The totals of an account kept from its messages: what was put in, net
/// of what came out, what it earned, and where its figures come from.
class _MemberTotals extends StatelessWidget {
  const _MemberTotals({required this.account, required this.today});

  final SavingsAccountSummary account;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final currency = account.currency;
    final product = account.product!;
    String plain(int minor) =>
        shownMoney(context, minor, currency: currency, withCurrency: false);
    final latest = account.entries.isEmpty ? null : account.entries.first.at;
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    final rows = <Widget>[
      _Fact(
        SavingsText.putIn,
        plain(account.putInMinor - account.takenOutMinor),
      ),
      _Fact(
        product.invested
            ? SavingsText.returnsEarned
            : SavingsText.interestEarned,
        _signed(context, account.interestMinor, currency),
      ),
      if (account.wasThereBeforeMinor != 0)
        _Fact(
          SavingsText.wasThereBefore,
          _signed(context, account.wasThereBeforeMinor, currency),
        ),
      if (account.otherChangesMinor != 0)
        _Fact(
          SavingsText.otherChanges,
          _signed(context, account.otherChangesMinor, currency),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Layout.cardPadding,
          vertical: 12,
        ),
        child: IconLine(
          icon: Icons.chat_bubble_outline,
          iconSize: 16,
          gap: 10,
          text: TextSpan(
            children: [
              const TextSpan(text: 'From your '),
              TextSpan(
                text: SavingsText.messagesFrom(product),
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(
                text: latest == null
                    ? ' messages'
                    : ' messages · ${dayLabel(CalendarDate.local(latest), thisYear: today.year)}',
              ),
            ],
          ),
          style: muted,
        ),
      ),
    ];
    return Card(
      child: Column(
        children: [
          for (final (i, row) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1),
            row,
          ],
        ],
      ),
    );
  }
}

/// A total: [label] at the start, muted, and [value] at the end. As in
/// [LabelValueRow], the value takes its own line under the label when both
/// do not fit, so the amount is never split.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;

  /// Already formatted, and masked while amounts are hidden.
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final labelStyle = theme.textTheme.bodyMedium!.copyWith(
      color: colors.textMuted,
    );
    final valueStyle = AppTypography.rowAmount(theme.colorScheme.onSurface);
    final amount = FigureText(value, style: valueStyle);
    final needs =
        _widestWord(context, label, labelStyle) +
        Layout.cardGap +
        FigureText.numberWidth(context, value, valueStyle);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Layout.cardPadding,
          vertical: 14,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => needs <= constraints.maxWidth
              ? Row(
                  children: [
                    Expanded(child: Text(label, style: labelStyle)),
                    const SizedBox(width: Layout.cardGap),
                    amount,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(label, style: labelStyle),
                    const SizedBox(height: 4),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: amount,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The widest word of [text] in [style] at the phone's text size.
double _widestWord(BuildContext context, String text, TextStyle style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.minIntrinsicWidth;
  painter.dispose();
  return width;
}

/// One goal: its name, what it holds and, when a Pesa Clarity goal is
/// saved in it, of what target with a bar; then whether it is locked, and
/// its code. Tapping it opens it.
class _PocketRow extends StatelessWidget {
  const _PocketRow({
    required this.pocket,
    required this.account,
    required this.today,
  });

  final SavingsPocket pocket;
  final SavingsAccountSummary account;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final currency = account.currency;
    final target = pocket.goalTargetMinor;
    final held = shownMoney(
      context,
      pocket.balanceMinor,
      currency: currency,
      withCurrency: false,
    );
    final of = target == null
        ? null
        : ' ${SavingsText.ofTarget(shownMoney(context, target, currency: currency, withCurrency: false))}';
    final amountStyle = AppTypography.amount(
      size: 16,
      color: theme.colorScheme.onSurface,
    );
    final ofStyle = theme.textTheme.bodySmall!.copyWith(
      color: colors.textMuted,
    );
    final amount = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: held, style: amountStyle),
          if (of != null) TextSpan(text: of, style: ofStyle),
        ],
      ),
      softWrap: false,
    );
    final nameStyle = theme.textTheme.bodyLarge!.copyWith(
      fontWeight: FontWeight.w500,
    );
    final captionStyle = theme.textTheme.bodySmall!.copyWith(
      color: colors.textMuted,
    );
    final locked = pocket.lockedUntil;
    final Widget caption = pocket.ignored
        ? Text(SavingsText.notYours(pocket.code), style: captionStyle)
        : locked != null && pocket.isLockedOn(today)
        ? IconLine(
            icon: Icons.lock_outline,
            iconSize: 15,
            text: TextSpan(
              text: SavingsText.lockedLine(locked, pocket.code, today.year),
            ),
            style: captionStyle,
          )
        : Text(SavingsText.openLine(pocket.code), style: captionStyle);
    final progress = target == null || target <= 0
        ? null
        : math.min(1, pocket.balanceMinor / target).toDouble();
    final needs =
        _widestWord(context, pocket.name, nameStyle) +
        Layout.cardGap +
        textLineWidth(context, held, amountStyle) +
        (of == null ? 0 : textLineWidth(context, of, ofStyle));
    return InkWell(
      key: Key('savings-pocket-${pocket.id}'),
      onTap: () => showSavingsPocketSheet(context, pocket),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Layout.cardPadding,
          vertical: 12,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => needs <= constraints.maxWidth
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(child: Text(pocket.name, style: nameStyle)),
                        const SizedBox(width: Layout.cardGap),
                        amount,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(pocket.name, style: nameStyle),
                        const SizedBox(height: 2),
                        amount,
                      ],
                    ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                color: colors.link,
                backgroundColor: colors.border,
                semanticsLabel: '${(progress * 100).floor()}% saved',
              ),
            ],
            const SizedBox(height: 6),
            caption,
          ],
        ),
      ),
    );
  }
}

/// A row of Recent: an icon in a soft square, a name and a line under it,
/// and an amount at the end, as Activity's rows are.
class _RecentRow extends StatelessWidget {
  const _RecentRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Already formatted, and masked while amounts are hidden.
  final String amount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Layout.cardPadding,
          vertical: 10,
        ),
        child: Row(
          children: [
            IconBadge(icon),
            const SizedBox(width: 12),
            Expanded(
              // At large text the amount moves under the name rather than
              // breaking it.
              child: BesideOrUnder(
                gap: 12,
                lead: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RowName(title, style: theme.textTheme.titleMedium),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
                end: readAsAmount(
                  amount,
                  Text(
                    amount,
                    style: AppTypography.rowAmount(theme.colorScheme.onSurface),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({
    required this.entry,
    required this.account,
    required this.accounts,
    required this.today,
  });

  final SavingsEntry entry;
  final SavingsAccountSummary account;
  final Map<int, Account> accounts;
  final CalendarDate today;

  Future<void> _chooseGoal(BuildContext context, WidgetRef ref) async {
    final picked = await showOptionSheet<int>(
      context,
      title: SavingsText.whichGoalTitle,
      options: [for (final p in account.pockets) (p.id, p.name)],
      selected: entry.pocketId,
    );
    if (picked == null) return;
    await ref
        .read(savingsRepositoryProvider)
        .assignEntry(entry.transactionId, picked);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final other = accounts[entry.otherAccountId]?.name ?? 'M-Pesa';
    final pocket = account.pocket(entry.pocketId);
    final day = SavingsText.day(CalendarDate.local(entry.at), today.year);
    final paidIn = entry.isPaidIn;
    final product = account.product;
    final byCode = product?.goalsByCode ?? true;
    final lead = paidIn
        ? (product != null && product.keptOnItsOwn
              ? SavingsText.movedFrom(other, invested: product.invested)
              : SavingsText.fromAccount(other))
        : SavingsText.withdrawnTo(other);
    return _RecentRow(
      key: Key('savings-entry-${entry.transactionId}'),
      icon: Icons.swap_horiz,
      // As money in names its goal after the account, money out names it
      // in the line under.
      title: paidIn && byCode ? [lead, ?pocket?.name].join(' · ') : lead,
      subtitle: [
        SavingsText.ownTransfer,
        if (!paidIn && byCode) pocket?.name ?? SavingsText.whichGoal,
        day,
      ].join(' · '),
      amount: _signed(context, entry.signedMinor, account.currency),
      // Money taken out can be put in a goal; money paid in stays in its
      // code's.
      onTap: paidIn || !byCode || account.pockets.isEmpty
          ? null
          : () => _chooseGoal(context, ref),
    );
  }
}

class _UpdateRow extends ConsumerWidget {
  const _UpdateRow({
    required this.update,
    required this.account,
    required this.today,
  });

  final UpdateOutcome update;
  final SavingsAccountSummary account;
  final CalendarDate today;

  Future<void> _undo(BuildContext context, WidgetRef ref, String day) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(savingsRepositoryProvider);
    final yes = await confirmDelete(
      context,
      title: '${SavingsText.undoUpdate}?',
      body: SavingsText.undoUpdateBody(day),
      action: 'Undo',
    );
    if (!yes) return;
    await repository.undoUpdate(account.accountId, update.at);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(SavingsText.updateUndone)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = account.currency;
    String plain(int minor) => shownMoney(
      context,
      minor.abs(),
      currency: currency,
      withCurrency: false,
    );
    final day = SavingsText.day(CalendarDate.local(update.at), today.year);
    final parts = [
      if (update.interestMinor != 0)
        SavingsText.includesInterest(plain(update.interestMinor)),
      if (update.wasThereBeforeMinor != 0)
        SavingsText.includesBefore(plain(update.wasThereBeforeMinor)),
      if (update.otherChangesMinor != 0)
        SavingsText.includesOther(
          _signed(context, update.otherChangesMinor, currency),
        ),
    ];
    final change = update.changeMinor;
    final product = account.product;
    final fromMessages = product?.balanceInMessages ?? false;
    // What an M-Pesa account earned reads as its returns or interest, as
    // Activity files it.
    if (product != null &&
        product.keptOnItsOwn &&
        update.interestMinor != 0 &&
        update.wasThereBeforeMinor == 0 &&
        update.otherChangesMinor == 0) {
      return _RecentRow(
        key: Key('savings-update-${update.at.millisecondsSinceEpoch}'),
        icon: Icons.trending_up,
        title: product.invested ? SavingsText.returns : SavingsText.interest,
        subtitle: [SavingsText.interest, day].join(' · '),
        amount: _signed(context, update.interestMinor, currency),
        onTap: fromMessages ? null : () => _undo(context, ref, day),
      );
    }
    return _RecentRow(
      key: Key('savings-update-${update.at.millisecondsSinceEpoch}'),
      icon: Icons.refresh,
      title: SavingsText.balanceUpdated,
      subtitle: [
        if (parts.isEmpty) SavingsText.noChange else ...parts,
        day,
      ].join(' · '),
      amount: change == 0 ? '0' : _signed(context, change, currency),
      // A balance its messages print follows them.
      onTap: fromMessages ? null : () => _undo(context, ref, day),
    );
  }
}

Future<void> _showRenameSheet(
  BuildContext context,
  SavingsAccountSummary account,
) => showAppSheet<void>(
  context: context,
  builder: (context) => _RenameSheet(account),
);

class _RenameSheet extends ConsumerStatefulWidget {
  const _RenameSheet(this.account);

  final SavingsAccountSummary account;

  @override
  ConsumerState<_RenameSheet> createState() => _RenameSheetState();
}

class _RenameSheetState extends ConsumerState<_RenameSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.account.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    await ref
        .read(savingsRepositoryProvider)
        .rename(widget.account.accountId, _name.text.trim());
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: SheetBody(
      title: SavingsText.changeName,
      children: [
        LabeledField(
          label: SavingsText.name,
          child: TextFormField(
            key: const Key('savings-rename-field'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 80,
            validator: (text) =>
                (text ?? '').trim().isEmpty ? 'Enter a name.' : null,
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('savings-rename-save'),
          onPressed: _save,
          child: const Text(SavingsText.save),
        ),
      ],
    ),
  );
}
