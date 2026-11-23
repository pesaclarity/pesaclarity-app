import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../data/repositories/sacco_links.dart';
import '../../../data/repositories/sacco_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/accounts/own_and_owe.dart';
import '../../../domain/debts/debt.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/format/date_labels.dart' show weekdayName;
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../shared/widgets/value_tile.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../balances/application/balances_providers.dart';
import '../../currency/application/currency_controller.dart';
import '../../debts/presentation/debts_screen.dart' show debtRateLabel;

/// Words for SACCOs.
abstract final class SaccoText {
  static const addSacco = 'Add a SACCO';
  static const addSaccoHint = 'Deposits, shares and a loan in one place';
  static const addIntro =
      'Type what your SACCO statement or app shows. Update it any time.';
  static const name = 'SACCO name';
  static const paybill = 'Its M-Pesa paybill';
  static String paybillNote(String name) =>
      'Payments to this paybill become moves to $name, your own money, not '
      'spending.';
  static const deposits = 'Deposits';
  static const shares = 'Shares';
  static const contribution = 'Monthly contribution';
  static const hasLoan = 'I have a loan here';
  static const hasLoanHint = 'It shows in Debts too';
  static const borrowTimes = 'It lets you borrow (optional)';
  static const borrowTimesHint = 'Such as 3 times your deposits';
  static const next = 'Continue';
  static String loanTitle(String name) => '$name loan';
  static const stepTwo = 'Step 2 of 2';
  static const owedNow = 'Owed now';
  static const rate = 'Interest a year';
  static const eachMonth = 'Each month';
  static const repaidBy = 'Repaid by';
  static const checkOff = 'Check-off from my salary';
  static String byPaybill(String? paybill) =>
      paybill == null ? 'M-Pesa paybill' : 'M-Pesa paybill ${spaced(paybill)}';
  static const payday = 'Payday';
  static String checkOffNote(String amount) =>
      'Check-off: your employer pays it before your salary reaches you, so no '
      'message comes. Pesa Clarity takes $amount off the loan each payday.';
  static String add(String name) => 'Add $name';
  static String added(String name) => '$name added.';
  static const saved = 'Saved';
  static String depositsAndShares(String deposits, String shares) =>
      'Deposits $deposits · shares $shares';
  static const sharesNote = "Shares can't be withdrawn.";
  static String contributionLine(String? paybill, String? paidFor) => [
    if (paybill != null) 'By paybill ${spaced(paybill)}',
    ?paidFor,
  ].join(' · ');
  static const loan = 'Loan';
  static String loanLine(String? rate, String monthly, bool checkOff) => [
    ?rate,
    '$monthly a month by ${checkOff ? 'check-off' : 'paybill'}',
  ].join(' · ');
  static const canBorrow = 'You can borrow up to';
  static String canBorrowLine(String times, String name) =>
      '$times times your deposits, as $name says';
  static const recent = 'Recent';
  static const deposit = 'Deposit';
  static const takenOut = 'Taken out';
  static const loanRepayment = 'Loan repayment';
  static const checkOffFromSalary = 'check-off from salary';
  static const byPaybillShort = 'by paybill';
  static String footer(String? paybill) => paybill == null
      ? 'Payments to your SACCO are moves, not spending.'
      : 'Payments to paybill ${spaced(paybill)} are moves to your SACCO, not '
            'spending.';
  static const nothingYet = 'Nothing yet. Payments to it show here.';
  static const savedLine = 'Saved: deposits and shares';
  static const owedLine = 'Owed · in Debts';
  static const ownOweNote =
      "The SACCO's deposits count under Saved and its loan under Owed. "
      'Neither counts in On hand or Safe to spend.';
  static const edit = 'Edit';

  /// `400222` as `400 222`.
  static String spaced(String digits) => digits.length == 6
      ? '${digits.substring(0, 3)} ${digits.substring(3)}'
      : digits;
}

/// Opens "Add a SACCO".
Future<void> showAddSaccoSheet(BuildContext context) =>
    showAppSheet<void>(context: context, builder: (_) => const AddSaccoSheet());

/// "Add a SACCO": its name, paybill, deposits, shares and contribution, then
/// its loan, if there is one, as step 2.
class AddSaccoSheet extends ConsumerStatefulWidget {
  const AddSaccoSheet({super.key});

  @override
  ConsumerState<AddSaccoSheet> createState() => _AddSaccoSheetState();
}

class _AddSaccoSheetState extends ConsumerState<AddSaccoSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _paybill = TextEditingController();
  final _deposits = TextEditingController();
  final _shares = TextEditingController();
  final _contribution = TextEditingController();
  final _borrow = TextEditingController();
  final _owed = TextEditingController();
  final _rate = TextEditingController();
  final _monthly = TextEditingController();
  var _hasLoan = false;
  var _step = 1;
  var _checkOff = true;
  var _payday = 28;
  var _saving = false;

  @override
  void dispose() {
    for (final c in [
      _name,
      _paybill,
      _deposits,
      _shares,
      _contribution,
      _borrow,
      _owed,
      _rate,
      _monthly,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _named =>
      _name.text.trim().isEmpty ? 'your SACCO' : _name.text.trim();

  Future<void> _save(String currency) async {
    if (!_form.currentState!.validate()) return;
    if (_step == 1 && _hasLoan) {
      setState(() => _step = 2);
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    int amount(TextEditingController c) =>
        AmountField.amountFrom(c.text, currency: currency) ?? 0;
    final rate = double.tryParse(_rate.text.replaceAll('%', '').trim());
    final times = double.tryParse(_borrow.text.trim());
    final contribution = amount(_contribution);
    await ref
        .read(saccoRepositoryProvider)
        .add(
          name: _name.text,
          currency: currency,
          paybill: _paybill.text,
          depositsMinor: amount(_deposits),
          sharesMinor: amount(_shares),
          contributionMinor: contribution == 0 ? null : contribution,
          borrowTimesTenths: times == null || times <= 0
              ? null
              : (times * 10).round(),
          at: ref.read(clockProvider)(),
          loan: _hasLoan
              ? SaccoLoanInput(
                  owedMinor: amount(_owed),
                  monthlyMinor: amount(_monthly),
                  rateBasisPoints: rate == null ? null : (rate * 100).round(),
                  checkOff: _checkOff,
                  checkOffDay: _payday,
                )
              : null,
        );
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(SaccoText.added(_name.text.trim()))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(baseCurrencyProvider);
    return Form(
      key: _form,
      child: _step == 1 ? _first(currency) : _second(currency),
    );
  }

  Widget _first(String currency) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(
      color: PesaColors.of(context).textMuted,
    );
    return SheetBody(
      title: SaccoText.addSacco,
      subtitle: SaccoText.addIntro,
      children: [
        LabeledField(
          label: SaccoText.name,
          child: TextFormField(
            key: const Key('sacco-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            validator: (t) => (t ?? '').trim().isEmpty
                ? 'Give it a name, such as Mwangaza SACCO.'
                : null,
          ),
        ),
        const SizedBox(height: Layout.cardGap),
        LabeledField(
          label: SaccoText.paybill,
          child: TextFormField(
            key: const Key('sacco-paybill'),
            controller: _paybill,
            keyboardType: TextInputType.number,
            validator: (t) {
              final digits = (t ?? '').replaceAll(RegExp(r'\s'), '');
              return digits.isEmpty || RegExp(r'^\d{5,7}$').hasMatch(digits)
                  ? null
                  : 'Type its paybill number, such as 400 222.';
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(SaccoText.paybillNote(_named), style: muted),
        const SizedBox(height: Layout.cardGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AmountField(
                key: const Key('sacco-deposits'),
                controller: _deposits,
                label: SaccoText.deposits,
                currency: currency,
                allowZero: true,
              ),
            ),
            const SizedBox(width: Layout.cardGap),
            Expanded(
              child: AmountField(
                key: const Key('sacco-shares'),
                controller: _shares,
                label: SaccoText.shares,
                currency: currency,
                allowZero: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: Layout.cardGap),
        AmountField(
          key: const Key('sacco-contribution'),
          controller: _contribution,
          label: SaccoText.contribution,
          currency: currency,
          allowZero: true,
        ),
        const SizedBox(height: Layout.cardGap),
        LabeledField(
          label: SaccoText.borrowTimes,
          child: TextFormField(
            key: const Key('sacco-borrow-times'),
            controller: _borrow,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              hintText: SaccoText.borrowTimesHint,
              suffixText: 'times',
            ),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          key: const Key('sacco-has-loan'),
          contentPadding: EdgeInsets.zero,
          value: _hasLoan,
          onChanged: (v) => setState(() => _hasLoan = v),
          title: const Text(SaccoText.hasLoan),
          subtitle: const Text(SaccoText.hasLoanHint),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('sacco-continue'),
          onPressed: _saving ? null : () => _save(currency),
          child: Text(_hasLoan ? SaccoText.next : SaccoText.add(_named)),
        ),
      ],
    );
  }

  Widget _second(String currency) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(
      color: PesaColors.of(context).textMuted,
    );
    final monthly = AmountField.amountFrom(_monthly.text, currency: currency);
    final paybill = saccoPaybill(_paybill.text);
    return SheetBody(
      title: SaccoText.loanTitle(_named),
      subtitle: SaccoText.stepTwo,
      children: [
        AmountField(
          key: const Key('sacco-owed'),
          controller: _owed,
          label: SaccoText.owedNow,
          currency: currency,
        ),
        const SizedBox(height: Layout.cardGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LabeledField(
                label: SaccoText.rate,
                child: TextFormField(
                  key: const Key('sacco-rate'),
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(suffixText: '%'),
                ),
              ),
            ),
            const SizedBox(width: Layout.cardGap),
            Expanded(
              child: AmountField(
                key: const Key('sacco-monthly'),
                controller: _monthly,
                label: SaccoText.eachMonth,
                currency: currency,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: Layout.cardGap),
        LabeledField(
          label: SaccoText.repaidBy,
          child: ChoiceMenu<bool>(
            key: const Key('sacco-repaid-by'),
            name: SaccoText.repaidBy,
            expand: true,
            options: [
              (true, SaccoText.checkOff),
              (false, SaccoText.byPaybill(paybill)),
            ],
            value: _checkOff,
            itemKey: (v) => Key('sacco-repaid-by-$v'),
            onChanged: (v) => setState(() => _checkOff = v),
          ),
        ),
        if (_checkOff) ...[
          const SizedBox(height: Layout.cardGap),
          ChoiceTile<int>(
            title: const Text(SaccoText.payday),
            trailing: ChoiceMenu<int>(
              key: const Key('sacco-payday'),
              name: SaccoText.payday,
              options: [for (var d = 1; d <= 31; d++) (d, _dayOfMonth(d))],
              value: _payday,
              onChanged: (d) => setState(() => _payday = d),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            SaccoText.checkOffNote(
              shownMoney(
                context,
                monthly ?? 0,
                currency: currency,
                withCurrency: false,
              ),
            ),
            style: muted,
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('sacco-add'),
          onPressed: _saving ? null : () => _save(currency),
          child: Text(SaccoText.add(_named)),
        ),
      ],
    );
  }
}

String _dayOfMonth(int d) {
  if (d >= 11 && d <= 13) return '${d}th';
  return switch (d % 10) {
    1 => '${d}st',
    2 => '${d}nd',
    3 => '${d}rd',
    _ => '${d}th',
  };
}

/// What a SACCO's page shows.
class SaccoView {
  const SaccoView({
    required this.account,
    required this.details,
    required this.savedMinor,
    required this.recent,
    this.loan,
    this.paidThisMonth = false,
  });

  final Account account;
  final SaccoDetailsRow details;

  /// Deposits and shares: the account's balance.
  final int savedMinor;
  final Debt? loan;
  final List<SaccoActivity> recent;

  /// Whether a deposit came in this month.
  final bool paidThisMonth;

  int get depositsMinor => savedMinor - details.sharesMinor;
}

final saccoViewProvider = FutureProvider.autoDispose.family<SaccoView?, int>((
  ref,
  accountId,
) async {
  ref.watch(ledgerChangesProvider);
  final repository = ref.watch(saccoRepositoryProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final db = ref.watch(appDatabaseProvider);
  await takeCheckOffs(db, today);
  final details = await saccoDetailsOf(db, accountId);
  final overview = await ref.watch(balancesOverviewProvider.future);
  final balance = overview.byId(accountId);
  if (details == null || balance == null) return null;
  final loan = details.loanDebtId == null
      ? null
      : (await ref.watch(debtsRepositoryProvider).debts(today: today))
            .where((d) => d.id == details.loanDebtId)
            .firstOrNull;
  final recent = await repository.recent(accountId);
  final month = today.yearMonth;
  return SaccoView(
    account: balance.account,
    details: details,
    savedMinor: balance.heldMinor,
    loan: loan,
    recent: recent,
    paidThisMonth: recent.any(
      (r) =>
          r.kind == SaccoActivityKind.deposit &&
          CalendarDate.local(r.at).yearMonth == month,
    ),
  );
});

/// Opens SACCO [accountId]'s page.
Future<void> openSaccoScreen(BuildContext context, int accountId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SaccoScreen(accountId: accountId),
      ),
    );

/// A SACCO's page: Saved (deposits and shares), its contribution, its loan
/// and what it lets the person borrow, and what happened lately.
class SaccoScreen extends ConsumerWidget {
  const SaccoScreen({required this.accountId, this.onEdit, super.key});

  final int accountId;

  /// Opens the account's page, to edit it.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(saccoViewProvider(accountId));
    final view = state.value;
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    String plain(int minor) => shownMoney(
      context,
      minor,
      currency: view?.account.currency,
      withCurrency: false,
    );
    Widget row(String title, String amount, String subtitle, {Key? key}) =>
        ValueTile(
          key: key,
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Text(
            amount,
            style: AppTypography.rowAmount(theme.colorScheme.onSurface),
          ),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(view?.account.name ?? ''),
        actions: [
          if (onEdit != null)
            IconButton(
              tooltip: SaccoText.edit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: onEdit,
            ),
          const AmountsEye(),
          const SizedBox(width: 8),
        ],
      ),
      body: view == null
          ? state.hasError
                ? ErrorView(
                    'This SACCO could not load.',
                    onRetry: () => ref.invalidate(saccoViewProvider(accountId)),
                  )
                : const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Layout.gutter,
                8,
                Layout.gutter,
                Layout.screenBottom,
              ),
              children: [
                Card(
                  key: const Key('sacco-saved'),
                  child: Padding(
                    padding: const EdgeInsets.all(Layout.cardPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          SaccoText.saved,
                          style: theme.textTheme.bodyMedium!.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                        const SizedBox(height: 4),
                        FigureText(
                          plain(view.savedMinor),
                          style: AppTypography.headlineFigure(
                            theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          SaccoText.depositsAndShares(
                            plain(view.depositsMinor),
                            plain(view.details.sharesMinor),
                          ),
                          style: theme.textTheme.bodySmall,
                        ),
                        if (view.details.sharesMinor > 0)
                          Text(SaccoText.sharesNote, style: muted),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Layout.cardGap),
                Card(
                  child: Column(
                    children: [
                      if (view.details.contributionMinor case final c?)
                        row(
                          SaccoText.contribution,
                          plain(c),
                          SaccoText.contributionLine(
                            saccoPaybill(view.details.paybill),
                            view.paidThisMonth
                                ? 'paid for '
                                      '${monthName(CalendarDate.local(ref.watch(clockProvider)()).yearMonth)}'
                                : null,
                          ),
                          key: const Key('sacco-contribution-row'),
                        ),
                      if (view.loan case final loan?) ...[
                        if (view.details.contributionMinor != null)
                          const Divider(height: 1),
                        row(
                          SaccoText.loan,
                          plain(loan.balanceMinor),
                          SaccoText.loanLine(
                            loan.chargesInterest
                                ? '${debtRateLabel(loan.annualRateBasisPoints)} a year'
                                : null,
                            plain(loan.minimumPaymentMinor),
                            view.details.checkOff,
                          ),
                          key: const Key('sacco-loan-row'),
                        ),
                      ],
                      if (view.details.borrowTimesTenths case final t?) ...[
                        const Divider(height: 1),
                        row(
                          SaccoText.canBorrow,
                          plain(
                            view.depositsMinor * t ~/ 10 -
                                (view.loan?.balanceMinor ?? 0),
                          ),
                          SaccoText.canBorrowLine(
                            t % 10 == 0 ? '${t ~/ 10}' : '${t / 10}',
                            view.account.name,
                          ),
                          key: const Key('sacco-can-borrow'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SectionLabel(SaccoText.recent),
                Card(
                  child: view.recent.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(Layout.cardPadding),
                          child: Text(SaccoText.nothingYet),
                        )
                      : Column(
                          children: [
                            for (final (i, r) in view.recent.indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              _ActivityRow(r, currency: view.account.currency),
                            ],
                          ],
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  SaccoText.footer(saccoPaybill(view.details.paybill)),
                  style: muted,
                ),
              ],
            ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow(this.activity, {required this.currency});

  final SaccoActivity activity;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final r = activity;
    final day = CalendarDate.local(r.at);
    final when = '${weekdayName(day).substring(0, 3)} ${dayLabel(day)}';
    final (title, line) = switch (r.kind) {
      SaccoActivityKind.deposit => (
        SaccoText.deposit,
        [
          when,
          if (r.from != null) 'from ${r.from}',
          if (r.ownTransfer) 'own transfer',
        ].join(' · '),
      ),
      SaccoActivityKind.takenOut => (SaccoText.takenOut, when),
      SaccoActivityKind.loanByPaybill => (
        SaccoText.loanRepayment,
        '$when · ${SaccoText.byPaybillShort}',
      ),
      SaccoActivityKind.checkOff => (
        SaccoText.loanRepayment,
        '$when · ${SaccoText.checkOffFromSalary}',
      ),
    };
    final amount = shownMoney(
      context,
      r.signedMinor.abs(),
      currency: currency,
      withCurrency: false,
    );
    final positive = r.signedMinor > 0;
    return ValueTile(
      title: Text(title),
      subtitle: Text(line),
      trailing: Text(
        '${positive ? '+' : '-'}$amount',
        style: AppTypography.rowAmount(
          positive ? colors.successText : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// The SACCOs on My accounts: each one's Saved and its loan's Owed.
class SaccosCard extends ConsumerWidget {
  const SaccosCard({required this.onOpen, super.key});

  final void Function(int accountId) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saccos = ref.watch(saccosProvider).value ?? const [];
    final overview = ref.watch(balancesOverviewProvider).value;
    final debts = ref.watch(saccoLoansProvider).value ?? const {};
    if (saccos.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    String plain(int minor, String currency) =>
        shownMoney(context, minor, currency: currency, withCurrency: false);
    final rows = <Widget>[];
    for (final (account, details) in saccos) {
      if (account.hidden) continue;
      final held = overview?.byId(account.id)?.heldMinor ?? 0;
      rows.add(
        ValueTile(
          key: Key('sacco-row-${account.id}'),
          title: Text(account.name),
          subtitle: const Text(SaccoText.savedLine),
          trailing: Text(
            plain(held, account.currency),
            style: AppTypography.rowAmount(theme.colorScheme.onSurface),
          ),
          onTap: () => onOpen(account.id),
        ),
      );
      if (debts[details.loanDebtId] case final loan?) {
        rows.add(
          ValueTile(
            key: Key('sacco-loan-row-${account.id}'),
            title: Text(loan.lender),
            subtitle: const Text(SaccoText.owedLine),
            trailing: Text(
              plain(-loan.balanceMinor, loan.currency),
              style: AppTypography.rowAmount(theme.colorScheme.onSurface),
            ),
            onTap: () => onOpen(account.id),
          ),
        );
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          key: const Key('saccos-card'),
          child: Column(
            children: [
              for (final (i, r) in rows.indexed) ...[
                if (i > 0) const Divider(height: 1),
                r,
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          SaccoText.ownOweNote,
          style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}

/// Every SACCO with its details.
final saccosProvider = StreamProvider<List<(Account, SaccoDetailsRow)>>(
  (ref) => ref.watch(saccoRepositoryProvider).watchAll(),
);

/// Each SACCO the person has not hidden, as "What you own and owe" counts
/// it: deposits and shares under Saved, its loan under Owed.
final saccoHoldingsProvider = Provider<List<SaccoHolding>>((ref) {
  final saccos = ref.watch(saccosProvider).value ?? const [];
  final overview = ref.watch(balancesOverviewProvider).value;
  final loans = ref.watch(saccoLoansProvider).value ?? const {};
  return [
    for (final (account, details) in saccos)
      if (!account.hidden)
        SaccoHolding(
          name: account.name,
          currency: account.currency,
          savedMinor: overview?.byId(account.id)?.heldMinor ?? 0,
          sharesMinor: details.sharesMinor,
          loanName: loans[details.loanDebtId]?.lender,
          loanOwedMinor: loans[details.loanDebtId]?.balanceMinor ?? 0,
        ),
  ];
});

/// The SACCOs' loans, by debt id.
final saccoLoansProvider = FutureProvider<Map<int, Debt>>((ref) async {
  ref.watch(ledgerChangesProvider);
  final saccos = await ref.watch(saccosProvider.future);
  final ids = {for (final (_, d) in saccos) ?d.loanDebtId};
  if (ids.isEmpty) return const {};
  final today = CalendarDate.local(ref.watch(clockProvider)());
  return {
    for (final d
        in await ref.watch(debtsRepositoryProvider).debts(today: today))
      if (ids.contains(d.id)) d.id: d,
  };
});
