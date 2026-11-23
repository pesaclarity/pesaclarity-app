import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database_providers.dart';
import '../../../domain/accounts/own_and_owe.dart';
import '../../../domain/savings/savings_account.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../balances/presentation/balances_screen.dart';
import '../../debts/presentation/due_line.dart' show IconLine;
import '../../savings/presentation/savings_account_screen.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/mpesa_family_providers.dart';

/// The words of the M-Pesa family on My accounts (decision 0026).
abstract final class FamilyText {
  static const ownAndOwe = 'What you own and owe';
  static String afterDebtsLine(String own, String owe) =>
      'Yours after debts · own $own, owe $owe';
  static const mpesa = 'M-Pesa';
  static const saved = 'Saved';
  static const invested = 'Invested';
  static const owed = 'Owed';
  static const wallet = 'Wallet';
  static const business = 'Business';
  static String linked(int count) =>
      'Wallet and $count linked ${count == 1 ? 'account' : 'accounts'}';
  static const afterDebts = 'after debts';
  static const walletChip = 'M-Pesa wallet';
  static String owedChip(int count) => '$count owed';
  static String show(int count) => 'Show $count accounts';
  static const hide = 'Hide accounts';
  static const yourBalance = 'Your M-Pesa balance';
  static const savings = 'Savings';
  static const fund = 'Money market fund';
  static String returnsThisMonth(String amount) =>
      '+$amount returns this month';
  static const fuliza = 'Fuliza';
  static const fulizaLine = 'Repaid from the next money in';
  static const countsInBusiness = 'Counts in your Business space';
  static const businessTill = 'Your business till';
  static String across(String day) => 'Across your M-Pesa accounts · $day';
  static String acrossAll(String day) => 'Across your accounts · $day';
  static String saccoDeposits(String name) => '$name deposits';
  static String saccoShares(String name) => "$name shares · can't be withdrawn";
  static const yoursAfterDebts = 'Yours after debts';
  static String pochiNote(String name, String amount, {required bool there}) =>
      there
      ? '$name ($amount) counts in your Business space, so it is not added '
            'here.'
      : '$name ($amount) is your business money, so it is not added here.';
  static const pochiChip = 'Pochi';
}

/// Whether the open space hands Pochi's money to a business: Personal,
/// with a business space beside it.
bool _pochiCountsElsewhere(WidgetRef ref) {
  if (ref.watch(activeSpaceIdProvider) != personalSpaceId) return false;
  final spaces = ref.watch(spacesProvider).value ?? const <Space>[];
  return spaces.any((s) => s.kind == SpaceKind.business);
}

/// The colours of the family's parts: the wallet grey, saved teal and
/// invested blue, as the approved mockup shows them. Owed is a ring.
({Color wallet, Color saved, Color invested}) _partColors(PesaColors colors) =>
    (
      wallet: colors.textMuted,
      saved: colors.markTeal,
      invested: colors.markBlue,
    );

/// The totals of [families] with [saccos] added, in the families' currency
/// or else the first SACCO's.
OwnAndOwe _totals(List<MpesaFamily> families, List<SaccoHolding> saccos) {
  int sum(int Function(MpesaFamily f) of) =>
      families.fold(0, (total, f) => total + of(f));
  return OwnAndOwe.of(
    currency: _currencyOf(families, saccos),
    walletMinor: sum((f) => f.walletMinor),
    savedMinor: sum((f) => f.savedMinor),
    investedMinor: sum((f) => f.investedMinor),
    owedMinor: sum((f) => f.owedMinor),
    saccos: saccos,
  );
}

String _currencyOf(List<MpesaFamily> families, List<SaccoHolding> saccos) =>
    families.firstOrNull?.currency ?? saccos.first.currency;

/// "What you own and owe", at the top of My accounts: what the M-Pesa
/// families and SACCOs hold after debts, a bar of their parts and each
/// part's total. Opens the breakdown. Needs a family or a SACCO.
class OwnAndOweCard extends StatelessWidget {
  const OwnAndOweCard({
    required this.families,
    this.saccos = const [],
    super.key,
  }) : assert(families.length + saccos.length > 0, 'needs an account');

  final List<MpesaFamily> families;

  /// SACCOs: deposits and shares under Saved, the loan under Owed.
  final List<SaccoHolding> saccos;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final parts = _partColors(colors);
    final currency = _currencyOf(families, saccos);
    final totals = _totals(families, saccos);
    final walletMinor = totals.walletMinor;
    final savedMinor = totals.savedMinor;
    final investedMinor = totals.investedMinor;
    final owedMinor = totals.owedMinor;
    final ownMinor = totals.ownMinor;
    String plain(int minor) =>
        shownMoney(context, minor, currency: currency, withCurrency: false);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    final legend = [
      if (families.isNotEmpty)
        (FamilyText.mpesa, walletMinor, parts.wallet, false),
      (FamilyText.saved, savedMinor, parts.saved, false),
      (FamilyText.invested, investedMinor, parts.invested, false),
      (FamilyText.owed, owedMinor, colors.textMuted, true),
    ];
    final bar = [
      (walletMinor, parts.wallet),
      (savedMinor, parts.saved),
      (investedMinor, parts.invested),
    ].where((p) => p.$1 > 0).toList();
    return Card(
      key: const Key('own-and-owe'),
      child: InkWell(
        onTap: () => showOwnAndOweSheet(context, families, saccos: saccos),
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      FamilyText.ownAndOwe,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Icon(Icons.chevron_right, color: colors.textMuted),
                ],
              ),
              const SizedBox(height: 6),
              FigureText(
                shownMoney(
                  context,
                  ownMinor - owedMinor,
                  currency: currency,
                  withCurrency: true,
                ),
                style: AppTypography.headlineFigure(
                  theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                FamilyText.afterDebtsLine(plain(ownMinor), plain(owedMinor)),
                style: muted,
              ),
              if (bar.isNotEmpty) ...[
                const SizedBox(height: 12),
                ExcludeSemantics(
                  child: Row(
                    children: [
                      for (final (i, (minor, color)) in bar.indexed) ...[
                        if (i > 0) const SizedBox(width: 2),
                        Expanded(
                          flex: minor,
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns =
                      MediaQuery.textScalerOf(context).scale(1) >= 1.3 ? 2 : 4;
                  final width =
                      constraints.maxWidth /
                      (columns > legend.length ? legend.length : columns);
                  return Wrap(
                    runSpacing: 10,
                    children: [
                      for (final (label, minor, color, ring) in legend)
                        SizedBox(
                          width: width,
                          child: MergeSemantics(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _Dot(color: color, ring: ring),
                                    const SizedBox(width: 5),
                                    Flexible(child: Text(label, style: muted)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  plain(minor),
                                  style: AppTypography.amount(
                                    size: 16,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A part's dot, or a ring for what is owed.
class _Dot extends StatelessWidget {
  const _Dot({required this.color, this.ring = false});

  final Color color;
  final bool ring;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: ring ? null : color,
      border: ring ? Border.all(color: color, width: 1.5) : null,
    ),
  );
}

/// The breakdown of "What you own and owe": every M-Pesa account under
/// M-Pesa, Saved, Invested and Owed, with each SACCO's deposits and shares
/// under Saved and its loan under Owed, then what is the person's after
/// debts.
Future<void> showOwnAndOweSheet(
  BuildContext context,
  List<MpesaFamily> families, {
  List<SaccoHolding> saccos = const [],
}) => showAppSheet<void>(
  context: context,
  builder: (context) =>
      AmountsHiddenScope(child: _OwnAndOweSheet(families, saccos)),
);

class _OwnAndOweSheet extends ConsumerWidget {
  const _OwnAndOweSheet(this.families, this.saccos);

  final List<MpesaFamily> families;
  final List<SaccoHolding> saccos;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final parts = _partColors(colors);
    final today = ref.watch(familyMonthProvider);
    final currency = _currencyOf(families, saccos);
    final totals = _totals(families, saccos);
    final saccosHere = [
      for (final s in saccos)
        if (s.currency == currency) s,
    ];
    final saccoLoans = [
      for (final s in saccosHere)
        if (s.hasLoan) s,
    ];
    String plain(int minor) =>
        shownMoney(context, minor, currency: currency, withCurrency: false);
    final saved = [for (final f in families) ...f.saved];
    final invested = [for (final f in families) ...f.invested];
    final fuliza = [
      for (final f in families)
        if (f.fulizaOwedMinor > 0) f,
    ];
    final business = [for (final f in families) ...f.business];
    final head = theme.textTheme.bodyLarge!.copyWith(
      fontWeight: FontWeight.w600,
    );
    final member = theme.textTheme.bodyMedium!.copyWith(
      color: colors.textMuted,
    );
    Widget row(String label, int minor, {Widget? lead, bool group = false}) =>
        MergeSemantics(
          child: Padding(
            padding: EdgeInsets.only(top: group ? 10 : 6, bottom: 2),
            child: Row(
              children: [
                if (lead != null) ...[lead, const SizedBox(width: 6)],
                if (!group) const SizedBox(width: 14),
                Expanded(child: Text(label, style: group ? head : member)),
                const SizedBox(width: Layout.cardGap),
                Text(
                  plain(minor),
                  style: AppTypography.amount(
                    size: group ? 16 : 15,
                    weight: group ? FontWeight.w600 : FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
    final there = _pochiCountsElsewhere(ref);
    return SheetBody(
      title: FamilyText.ownAndOwe,
      subtitle: saccosHere.isEmpty
          ? FamilyText.across(dayLabel(today, thisYear: today.year))
          : FamilyText.acrossAll(dayLabel(today, thisYear: today.year)),
      children: [
        if (families.isNotEmpty)
          row(
            FamilyText.mpesa,
            totals.walletMinor,
            lead: _Dot(color: parts.wallet),
            group: true,
          ),
        if (saved.isNotEmpty || saccosHere.isNotEmpty) ...[
          row(
            FamilyText.saved,
            totals.savedMinor,
            lead: _Dot(color: parts.saved),
            group: true,
          ),
          for (final s in saved) row(s.name, s.balanceMinor),
          for (final s in saccosHere) ...[
            row(FamilyText.saccoDeposits(s.name), s.depositsMinor),
            if (s.sharesMinor > 0)
              row(FamilyText.saccoShares(s.name), s.sharesMinor),
          ],
        ],
        if (invested.isNotEmpty) ...[
          row(
            FamilyText.invested,
            totals.investedMinor,
            lead: _Dot(color: parts.invested),
            group: true,
          ),
          for (final s in invested) row(s.name, s.balanceMinor),
        ],
        row(
          FamilyText.owed,
          totals.owedMinor,
          lead: _Dot(color: colors.textMuted, ring: true),
          group: true,
        ),
        for (final f in fuliza) row(FamilyText.fuliza, f.fulizaOwedMinor),
        for (final s in saccoLoans) row(s.loanName!, s.loanOwedMinor),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 14),
        MergeSemantics(
          child: Row(
            children: [
              Expanded(child: Text(FamilyText.yoursAfterDebts, style: head)),
              const SizedBox(width: Layout.cardGap),
              Text(
                shownMoney(
                  context,
                  totals.afterDebtsMinor,
                  currency: currency,
                  withCurrency: true,
                ),
                style: AppTypography.amount(
                  size: 20,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        for (final b in business) ...[
          const SizedBox(height: 12),
          IconLine(
            icon: Icons.storefront_outlined,
            iconSize: 16,
            gap: 8,
            text: TextSpan(
              text: FamilyText.pochiNote(
                b.account.name,
                plain(b.heldMinor),
                there: there,
              ),
            ),
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
        ],
      ],
    );
  }
}

/// M-Pesa as a group on My accounts: the wallet and the accounts linked to
/// it, with what is the person's after debts. Closed, it names its members;
/// opened, each is a row that opens its own page.
class MpesaFamilyCard extends ConsumerStatefulWidget {
  const MpesaFamilyCard({required this.family, required this.name, super.key});

  final MpesaFamily family;

  /// The wallet's name, such as `M-Pesa` or a line's name.
  final String name;

  @override
  ConsumerState<MpesaFamilyCard> createState() => _MpesaFamilyCardState();
}

class _MpesaFamilyCardState extends ConsumerState<MpesaFamilyCard> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final family = widget.family;
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final currency = family.currency;
    final month = ref.watch(familyMonthProvider);
    String plain(int minor) =>
        shownMoney(context, minor, currency: currency, withCurrency: false);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    final total = family.linkedCount + 1;
    final there = _pochiCountsElsewhere(ref);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(widget.name, style: theme.textTheme.titleSmall),
                    Tag(currency),
                  ],
                ),
                const SizedBox(height: 2),
                Text(FamilyText.linked(family.linkedCount), style: muted),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                plain(family.afterDebtsMinor),
                style: AppTypography.rowAmount(theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 2),
              Text(FamilyText.afterDebts, style: muted),
            ],
          ),
        ],
      ),
    );

    final chips = Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 14),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          const _Chip(FamilyText.walletChip),
          for (final s in [...family.saved, ...family.invested]) _Chip(s.name),
          for (final _ in family.business) const _Chip(FamilyText.pochiChip),
          if (family.fulizaOwedMinor > 0)
            _Chip(FamilyText.owedChip(1), owed: true),
        ],
      ),
    );

    Widget sectionLabel(String text, [int? minor]) => SectionLabel(
      text,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
      trailing: minor == null
          ? null
          : Text(
              plain(minor),
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
    );

    String savedLine(SavingsAccountSummary s) {
      final earned = earnedIn(s, month);
      if (s.product?.invested ?? false) {
        return earned > 0
            ? FamilyText.returnsThisMonth(plain(earned))
            : FamilyText.fund;
      }
      return FamilyText.savings;
    }

    final members = <Widget>[
      sectionLabel(FamilyText.wallet),
      _MemberRow(
        key: Key('family-wallet-${family.wallet.account.id}'),
        name: FamilyText.mpesa,
        line: FamilyText.yourBalance,
        amount: plain(family.walletMinor),
        onTap: () => showAccountBalanceSheet(context, family.wallet),
      ),
      if (family.saved.isNotEmpty) ...[
        const Divider(height: 1),
        sectionLabel(FamilyText.saved, family.savedMinor),
        for (final (i, s) in family.saved.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _MemberRow(
            key: Key('family-member-${s.accountId}'),
            name: s.name,
            line: savedLine(s),
            amount: plain(s.balanceMinor),
            onTap: () => showSavingsAccount(context, s.accountId),
          ),
        ],
      ],
      if (family.invested.isNotEmpty) ...[
        const Divider(height: 1),
        sectionLabel(FamilyText.invested, family.investedMinor),
        for (final (i, s) in family.invested.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _MemberRow(
            key: Key('family-member-${s.accountId}'),
            name: s.name,
            line: savedLine(s),
            amount: plain(s.balanceMinor),
            onTap: () => showSavingsAccount(context, s.accountId),
          ),
        ],
      ],
      if (family.fulizaOwedMinor > 0) ...[
        const Divider(height: 1),
        sectionLabel(FamilyText.owed, family.owedMinor),
        _MemberRow(
          key: Key('family-fuliza-${family.wallet.account.id}'),
          name: FamilyText.fuliza,
          line: FamilyText.fulizaLine,
          amount: plain(family.fulizaOwedMinor),
          onTap: () => showAccountBalanceSheet(context, family.wallet),
        ),
      ],
      if (family.business.isNotEmpty) ...[
        const Divider(height: 1),
        sectionLabel(FamilyText.business),
        for (final (i, b) in family.business.indexed) ...[
          if (i > 0) const Divider(height: 1),
          _MemberRow(
            key: Key('family-member-${b.account.id}'),
            name: b.account.name,
            line: there ? FamilyText.countsInBusiness : FamilyText.businessTill,
            amount: plain(b.heldMinor),
            onTap: () => showAccountBalanceSheet(context, b),
          ),
        ],
      ],
    ];

    return Card(
      key: Key('mpesa-family-${family.wallet.account.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (_open) ...members else chips,
          const Divider(height: 1),
          TextButton(
            key: Key('mpesa-family-toggle-${family.wallet.account.id}'),
            onPressed: () => setState(() => _open = !_open),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(Layout.minTouch),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_open ? FamilyText.hide : FamilyText.show(total)),
                const SizedBox(width: 4),
                Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A member's name in a small rounded chip; an owed member's is outlined,
/// not filled.
class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.owed = false});

  final String text;
  final bool owed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: owed ? null : colors.border,
        border: owed ? Border.all(color: colors.border) : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall!.copyWith(
          fontWeight: FontWeight.w500,
          color: owed ? colors.textMuted : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// One member of the family: its name and a line under it, its amount and
/// a chevron. Opens its page.
class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.name,
    required this.line,
    required this.amount,
    required this.onTap,
    super.key,
  });

  final String name;
  final String line;

  /// Already formatted, and masked while amounts are hidden.
  final String amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleSmall),
                    Text(
                      line,
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Layout.cardGap),
              Text(
                amount,
                style: AppTypography.amount(
                  size: 17,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
