import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart' hide Tag;
import '../../../data/repositories/account_edits.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/accounts/account_reference.dart';
import '../../../domain/ledger/balances.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/states.dart';
import '../../../shared/widgets/value_tile.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../activity/application/activity_providers.dart';
import '../../balances/application/balances_providers.dart';
import '../../balances/presentation/set_balance_sheet.dart';
import '../domain/institution.dart';
import 'account_currency_screen.dart';

/// The kinds an account added by hand can be, in menu order.
const editableAccountTypes = [
  AccountType.cash,
  AccountType.bank,
  AccountType.mpesa,
  AccountType.moneyMarket,
  AccountType.sacco,
  AccountType.other,
];

/// What an account's type is called where the person chooses it.
String accountTypeChoice(AccountType type) => switch (type) {
  AccountType.cash => 'Cash',
  AccountType.bank => 'Bank',
  AccountType.mpesa => 'Mobile money',
  AccountType.moneyMarket => 'Savings app',
  AccountType.sacco => 'SACCO',
  AccountType.other => 'Other',
  AccountType.heldForSpace => 'Held for another space',
  AccountType.ownersAccount => "Owner's account",
  AccountType.paidBySpace => 'Paid by another space',
};

/// Whether [type] counts in On hand until the person says otherwise.
bool countsOnHandByType(AccountType type) =>
    !savingsAccountTypes.contains(type);

/// Words on the account page and its remove questions.
abstract final class AccountEditText {
  static const save = 'Save';
  static const name = 'Name';
  static const type = 'Type';
  static const currency = 'Currency';
  static const lastDigits = 'Last 4 digits (optional)';
  static const lastDigitsHint = 'Such as 4321';
  static const number = 'Number';
  static const openingBalance = 'Opening balance';
  static const openedOn = 'On';
  static const countOnHand = 'Count in On hand and Safe to spend';
  static const countOnHandHint = 'Off for savings you do not spend from';
  static const hide = 'Hide from lists';
  static const hideHint = 'It stays in totals and history';
  static const setBalance = 'Set the balance';
  static String appShows(String amount) => 'The app shows $amount';
  static const openingNote =
      'Changing the opening balance moves every balance after it. Set the '
      'balance adds a correction from today instead.';
  static const typeNote =
      'Type sets the starting point: Cash and Bank count in On hand; '
      'Savings app and SACCO do not. The switch above can change it.';
  static String lockedNote(String sender) =>
      'Set by its messages from $sender, so they stay as the messages say.';
  static const stopReading = 'Stop reading these messages';
  static String stopReadingHint(int count) =>
      'Opens Add or remove accounts. Its $count '
      '${count == 1 ? 'transaction stays' : 'transactions stay'}.';
  static String stopReadingNote(String sender) =>
      'Messages already read are kept, with their balances. New ones from '
      '$sender are not read until you switch it back on.';
  static String remove(String name) => 'Remove $name';
  static String removeQuestion(String name) => 'Remove $name?';
  static String nothingOnIt(String opening) =>
      'It has no transactions, so nothing else changes. Its opening balance '
      'of $opening leaves your totals.';
  static String hasTransactions(int count, String span, String holds) =>
      'It has $count ${count == 1 ? 'transaction' : 'transactions'}'
      '${span.isEmpty ? '' : ', $span,'} and holds $holds now.';
  static const hideKeep = 'Hide it and keep its history';
  static String hideKeepHint(int count, String amount) =>
      'Its $count ${count == 1 ? 'transaction stays' : 'transactions stay'} '
      'in Activity, Plan and Insights. Its $amount leaves every total. Show '
      'it again from Hidden accounts.';
  static const move = 'Move its transactions to another account';
  static String moveHint(String amount) =>
      'They join the account you pick. That account goes up by $amount; your '
      'totals stay the same.';
  static String deleteAll(int count) =>
      'Delete it and its $count ${count == 1 ? 'transaction' : 'transactions'}';
  static String deleteHint(String amount) =>
      'They leave Activity, Plan and Insights, and its $amount leaves every '
      'total. This cannot be undone.';
  static String hideButton(String name) => 'Hide $name';
  static String moveButton(int count) => 'Move $count and remove';
  static const deleteButton = 'Delete';
  static String deleteQuestion(String name, int count) =>
      'Delete $name and its $count '
      '${count == 1 ? 'transaction' : 'transactions'}?';
  static String deleteBody(String amount, int count) =>
      'Your totals drop by $amount, and Plan and Insights lose '
      '${count == 1 ? 'this one' : 'these $count'}. This cannot be undone.';
  static const moveTo = 'Move to';
  static const noOtherAccount = 'No other account counts in the same currency.';
  static String moveNote({
    required String target,
    required String from,
    required String to,
    required String name,
    required String change,
    required bool targetCounts,
    required bool thisCounts,
  }) {
    final first = '$target goes from $from to $to.';
    if (targetCounts == thisCounts) return '$first On hand stays the same.';
    return targetCounts
        ? '$first On hand goes up by $change too, as $target counts there '
              'and $name did not.'
        : '$first On hand goes down by $change, as $name counted there and '
              '$target does not.';
  }

  static const hiddenAccounts = 'Hidden accounts';
  static String saved(String name) => '$name saved.';
  static String removed(String name) => '$name removed.';
  static String hidden(String name) => '$name hidden.';
  static const currencyMissing =
      "That currency's rate on the opening day is missing, so the currency "
      'stayed as it was.';
}

/// Opens [account]'s page.
Future<void> openAccountPage(BuildContext context, int accountId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AccountPage(accountId: accountId),
      ),
    );

/// How many transactions an account has, and the first and last.
final accountStatsProvider = FutureProvider.autoDispose
    .family<({int count, DateTime? first, DateTime? last}), int>((
      ref,
      accountId,
    ) {
      ref.watch(ledgerChangesProvider);
      return ref.watch(accountEditsProvider).stats(accountId);
    });

/// My accounts › an account: its name, type, currency, last digits,
/// opening balance and date, whether it counts in On hand, and Hide from
/// lists, with Set the balance and Remove. An account read from messages
/// can only be renamed or hidden; its other details are its messages'.
class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({required this.accountId, super.key});

  final int accountId;

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _digits = TextEditingController();
  final _opening = TextEditingController();
  Account? _loaded;
  late AccountType _type;
  late CalendarDate _openedOn;
  bool? _counts;
  late bool _hidden;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _digits.dispose();
    _opening.dispose();
    super.dispose();
  }

  void _load(Account a) {
    _loaded = a;
    _name.text = a.name;
    _digits.text = AccountReference.tryParse(a.reference)?.lastDigits ?? '';
    _opening.text = _plain(a.openingBalanceMinor, a.currency);
    _type = a.type;
    _openedOn = CalendarDate.local(a.openingDate);
    _counts = a.countsOnHand;
    _hidden = a.hidden;
  }

  static String _plain(int minor, String currency) {
    if (minor == 0) return '';
    final whole = minor ~/ 100;
    final cents = (minor % 100).abs();
    return cents == 0 ? '$whole' : '$whole.${cents.toString().padLeft(2, '0')}';
  }

  bool get _countsNow => _counts ?? countsOnHandByType(_type);

  Future<void> _save() async {
    final account = _loaded!;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final edits = ref.read(accountEditsProvider);
    final byHand = account.institutionId == null;
    await edits.save(
      account.id,
      name: _name.text,
      type: byHand ? _type : null,
      lastDigits: byHand ? _digits.text : null,
      hidden: _hidden,
      countsOnHand: _counts,
      setCountsOnHand: byHand,
    );
    if (byHand) {
      final repository = ref.read(accountsRepositoryProvider);
      final opening =
          AmountField.amountFrom(_opening.text, currency: account.currency) ??
          account.openingBalanceMinor;
      final at = _openedOn == CalendarDate.local(account.openingDate)
          ? account.openingDate
          : _openedOn.startInstant;
      if (opening != account.openingBalanceMinor || at != account.openingDate) {
        await repository.setOpening(account.id, opening, at);
      }
    }
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AccountEditText.saved(_name.text.trim()))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(activityAccountsProvider);
    final account = accounts.value?[widget.accountId];
    if (account != null && _loaded?.id != account.id) _load(account);
    final balance = ref
        .watch(balancesOverviewProvider)
        .value
        ?.byId(widget.accountId);
    return Scaffold(
      appBar: AppBar(
        title: Text(account?.name ?? ''),
        actions: [
          if (account != null)
            TextButton(
              key: const Key('account-save'),
              onPressed: _saving ? null : _save,
              child: const Text(AccountEditText.save),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: account == null
          ? accounts.hasError
                ? ErrorView(
                    'This account could not load.',
                    onRetry: () => ref.invalidate(activityAccountsProvider),
                  )
                : const LoadingView()
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  Layout.gutter,
                  8,
                  Layout.gutter,
                  Layout.screenBottom,
                ),
                children: account.institutionId == null
                    ? _byHand(context, account, balance)
                    : _fromMessages(context, account, balance),
              ),
            ),
    );
  }

  Widget _nameField() => LabeledField(
    label: AccountEditText.name,
    child: TextFormField(
      key: const Key('account-name'),
      controller: _name,
      textCapitalization: TextCapitalization.words,
      maxLength: 80,
      buildCounter: (
        _, {
        required currentLength,
        required isFocused,
        maxLength,
      }) => null,
      validator: (text) =>
          (text ?? '').trim().isEmpty ? 'Give it a name, such as Cash.' : null,
    ),
  );

  Widget _hideSwitch() => SwitchListTile.adaptive(
    key: const Key('account-hide'),
    value: _hidden,
    onChanged: (v) => setState(() => _hidden = v),
    title: const Text(AccountEditText.hide),
    subtitle: const Text(AccountEditText.hideHint),
  );

  Widget? _setBalanceTile(AccountBalance? balance) => balance == null
      ? null
      : Card(
          child: ListTile(
            key: const Key('account-set-balance'),
            title: const Text(AccountEditText.setBalance),
            subtitle: Text(
              AccountEditText.appShows(
                shownMoney(
                  context,
                  balance.heldMinor,
                  currency: balance.account.currency,
                  withCurrency: true,
                ),
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showSetBalanceSheet(context, balance),
          ),
        );

  List<Widget> _byHand(
    BuildContext context,
    Account account,
    AccountBalance? balance,
  ) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final setBalance = _setBalanceTile(balance);
    return [
      _nameField(),
      const SizedBox(height: Layout.cardGap),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LabeledField(
              label: AccountEditText.type,
              child: ChoiceMenu<AccountType>(
                key: const Key('account-type'),
                name: AccountEditText.type,
                expand: true,
                options: [
                  for (final t in {...editableAccountTypes, account.type})
                    (t, accountTypeChoice(t)),
                ],
                value: _type,
                itemKey: (t) => Key('account-type-${t.name}'),
                onChanged: (t) => setState(() => _type = t),
              ),
            ),
          ),
          const SizedBox(width: Layout.cardGap),
          Expanded(
            child: LabeledField(
              label: AccountEditText.currency,
              child: Semantics(
                button: true,
                label:
                    '${AccountEditText.currency}: ${account.currency}. Change',
                excludeSemantics: true,
                child: OutlinedButton(
                  key: const Key('account-currency'),
                  // Asks first, as it always has: new amounts take it.
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AccountCurrencyScreen(accountId: account.id),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(account.currency)),
                      const Icon(Icons.arrow_drop_down),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: Layout.cardGap),
      LabeledField(
        label: AccountEditText.lastDigits,
        child: TextFormField(
          key: const Key('account-digits'),
          controller: _digits,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: AccountEditText.lastDigitsHint,
          ),
          validator: (text) {
            final digits = (text ?? '').replaceAll(RegExp(r'\s'), '');
            if (digits.isEmpty) return null;
            return RegExp(r'^\d{2,6}$').hasMatch(digits)
                ? null
                : 'Type the last digits, such as 4321.';
          },
        ),
      ),
      const SizedBox(height: Layout.cardGap),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: AmountField(
              key: const Key('account-opening'),
              controller: _opening,
              label: AccountEditText.openingBalance,
              currency: account.currency,
              allowZero: true,
            ),
          ),
          const SizedBox(width: Layout.cardGap),
          Expanded(
            child: DateField(
              key: const Key('account-opened-on'),
              label: AccountEditText.openedOn,
              value: _openedOn,
              firstDate: CalendarDate(2000, 1, 1),
              lastDate: today,
              onChanged: (d) {
                if (d != null) setState(() => _openedOn = d);
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: Layout.cardGap),
      Card(
        child: Column(
          children: [
            SwitchListTile.adaptive(
              key: const Key('account-on-hand'),
              value: _countsNow,
              onChanged: (v) => setState(() => _counts = v),
              title: const Text(AccountEditText.countOnHand),
              subtitle: const Text(AccountEditText.countOnHandHint),
            ),
            const Divider(height: 1),
            _hideSwitch(),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(AccountEditText.typeNote, style: muted),
      if (setBalance != null) ...[
        const SizedBox(height: Layout.cardGap),
        setBalance,
      ],
      const SizedBox(height: 8),
      Text(AccountEditText.openingNote, style: muted),
      const SizedBox(height: 24),
      OutlinedButton(
        key: const Key('account-remove'),
        onPressed: () => _remove(account, balance),
        child: Text(AccountEditText.remove(account.name)),
      ),
    ];
  }

  List<Widget> _fromMessages(
    BuildContext context,
    Account account,
    AccountBalance? balance,
  ) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    final institution = ref
        .watch(institutionCatalogueProvider)
        .where((i) => i.id == account.institutionId)
        .firstOrNull;
    final sender = institution == null
        ? account.institutionId!.toUpperCase()
        : (institution.senderIds.isEmpty
              ? institution.name
              : institution.senderIds.first);
    final count = ref.watch(accountStatsProvider(account.id)).value?.count;
    final number = AccountReference.tryParse(account.reference)?.label;
    Widget locked(String label, String value, Key key) => ValueTile(
      key: key,
      title: Text(label),
      trailing: Semantics(
        label: '$value, set by its messages',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 16, color: colors.textMuted),
            const SizedBox(width: 4),
            Text(value, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
    final setBalance = _setBalanceTile(balance);
    return [
      _nameField(),
      const SizedBox(height: Layout.cardGap),
      Card(
        child: Column(
          children: [
            locked(
              AccountEditText.type,
              accountTypeChoice(account.type),
              const Key('account-type-locked'),
            ),
            const Divider(height: 1),
            locked(
              AccountEditText.currency,
              account.currency,
              const Key('account-currency-locked'),
            ),
            if (number != null) ...[
              const Divider(height: 1),
              locked(
                AccountEditText.number,
                number,
                const Key('account-number-locked'),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 8),
      Text(AccountEditText.lockedNote(sender), style: muted),
      const SizedBox(height: Layout.cardGap),
      Card(child: _hideSwitch()),
      if (setBalance != null) ...[
        const SizedBox(height: Layout.cardGap),
        setBalance,
      ],
      const SizedBox(height: Layout.cardGap),
      Card(
        child: ListTile(
          key: const Key('account-stop-reading'),
          title: const Text(AccountEditText.stopReading),
          subtitle: count == null
              ? null
              : Text(AccountEditText.stopReadingHint(count)),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.chooseAccounts),
        ),
      ),
      const SizedBox(height: 8),
      Text(AccountEditText.stopReadingNote(sender), style: muted),
    ];
  }

  Future<void> _remove(Account account, AccountBalance? balance) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final edits = ref.read(accountEditsProvider);
    final stats = await edits.stats(account.id);
    if (!mounted) return;
    void done(String text) {
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }

    if (stats.count == 0) {
      final yes = await confirmDelete(
        context,
        title: AccountEditText.removeQuestion(account.name),
        body: AccountEditText.nothingOnIt(
          shownMoney(
            context,
            account.openingBalanceMinor,
            currency: account.currency,
            withCurrency: false,
          ),
        ),
        action: 'Remove',
      );
      if (!yes) return;
      await edits.delete(account.id);
      done(AccountEditText.removed(account.name));
      return;
    }
    final outcome = await showAppSheet<RemoveOutcome>(
      context: context,
      builder: (_) => AmountsHiddenScope(
        child: RemoveAccountSheet(
          account: account,
          count: stats.count,
          first: stats.first,
          last: stats.last,
          balance: balance,
        ),
      ),
    );
    if (outcome == null || !mounted) return;
    switch (outcome) {
      case RemoveHide():
        await edits.save(
          account.id,
          hidden: true,
          countsOnHand: false,
          setCountsOnHand: true,
        );
        done(AccountEditText.hidden(account.name));
      case RemoveMove(:final toId):
        await edits.moveAndRemove(account.id, toId);
        done(AccountEditText.removed(account.name));
      case RemoveDelete():
        await edits.delete(account.id);
        done(AccountEditText.removed(account.name));
    }
  }
}

/// What the person chose in [RemoveAccountSheet].
sealed class RemoveOutcome {
  const RemoveOutcome();
}

class RemoveHide extends RemoveOutcome {
  const RemoveHide();
}

class RemoveMove extends RemoveOutcome {
  const RemoveMove(this.toId);

  final int toId;
}

class RemoveDelete extends RemoveOutcome {
  const RemoveDelete();
}

enum _RemoveChoice { hide, move, delete }

/// "Remove Tumaini SACCO?" for an account with transactions: hide it and
/// keep its history, move its transactions to another account, or delete
/// it with them. Nothing is chosen until the person taps one.
class RemoveAccountSheet extends ConsumerStatefulWidget {
  const RemoveAccountSheet({
    required this.account,
    required this.count,
    this.first,
    this.last,
    this.balance,
    super.key,
  });

  final Account account;
  final int count;
  final DateTime? first;
  final DateTime? last;
  final AccountBalance? balance;

  @override
  ConsumerState<RemoveAccountSheet> createState() => _RemoveAccountSheetState();
}

class _RemoveAccountSheetState extends ConsumerState<RemoveAccountSheet> {
  _RemoveChoice? _choice;
  int? _to;

  String _span() {
    final first = widget.first;
    final last = widget.last;
    if (first == null || last == null) return '';
    final a = CalendarDate.local(first).yearMonth;
    final b = CalendarDate.local(last).yearMonth;
    if (a == b) return 'in ${monthLabel(a)}';
    return a.year == b.year
        ? '${monthName(a)} to ${monthLabel(b)}'
        : '${monthLabel(a)} to ${monthLabel(b)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final account = widget.account;
    final held = widget.balance?.heldMinor ?? 0;
    String money(int minor, {bool unit = false}) => shownMoney(
      context,
      minor,
      currency: account.currency,
      withCurrency: unit,
    );
    final overview = ref.watch(balancesOverviewProvider).value;
    final targets = [
      for (final a in overview?.accounts ?? const <AccountBalance>[])
        if (a.account.id != account.id &&
            a.account.currency == account.currency &&
            !a.account.type.isBetweenSpaces &&
            a.account.product == null)
          a,
    ];
    final target = targets.where((a) => a.account.id == _to).firstOrNull;
    final count = widget.count;

    Widget option(_RemoveChoice c, String title, String hint) {
      final chosen = _choice == c;
      return Semantics(
        selected: chosen,
        button: true,
        child: ListTile(
          key: Key('remove-${c.name}'),
          title: Text(
            title,
            style: theme.textTheme.bodyLarge!.copyWith(
              color: chosen ? colors.link : null,
            ),
          ),
          subtitle: Text(hint),
          trailing: chosen ? Icon(Icons.check, color: colors.link) : null,
          onTap: () => setState(() => _choice = c),
        ),
      );
    }

    final String? button = switch (_choice) {
      null => null,
      _RemoveChoice.hide => AccountEditText.hideButton(account.name),
      _RemoveChoice.move => AccountEditText.moveButton(count),
      _RemoveChoice.delete => AccountEditText.deleteButton,
    };
    final ready =
        _choice != null && (_choice != _RemoveChoice.move || target != null);
    return SheetBody(
      title: AccountEditText.removeQuestion(account.name),
      subtitle: AccountEditText.hasTransactions(
        count,
        _span(),
        money(held, unit: true),
      ),
      children: [
        Card(
          child: Column(
            children: [
              option(
                _RemoveChoice.hide,
                AccountEditText.hideKeep,
                AccountEditText.hideKeepHint(count, money(held)),
              ),
              const Divider(height: 1),
              option(
                _RemoveChoice.move,
                AccountEditText.move,
                AccountEditText.moveHint(money(held)),
              ),
              const Divider(height: 1),
              option(
                _RemoveChoice.delete,
                AccountEditText.deleteAll(count),
                AccountEditText.deleteHint(money(held)),
              ),
            ],
          ),
        ),
        if (_choice == _RemoveChoice.move) ...[
          const SizedBox(height: Layout.cardGap),
          if (targets.isEmpty)
            Text(
              AccountEditText.noOtherAccount,
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            LabeledField(
              label: AccountEditText.moveTo,
              child: ChoiceMenu<int?>(
                key: const Key('remove-move-to'),
                name: AccountEditText.moveTo,
                expand: true,
                options: [
                  if (_to == null) (null, 'Pick an account'),
                  for (final a in targets) (a.account.id, a.account.name),
                ],
                value: _to,
                itemKey: (id) => Key('remove-move-to-$id'),
                onChanged: (id) => setState(() => _to = id),
              ),
            ),
            if (target != null) ...[
              const SizedBox(height: 8),
              Text(
                AccountEditText.moveNote(
                  target: target.account.name,
                  from: money(target.heldMinor, unit: true),
                  to: money(target.heldMinor + held),
                  name: account.name,
                  change: money(held.abs()),
                  targetCounts: !target.isSavings,
                  thisCounts: !(widget.balance?.isSavings ?? true),
                ),
                key: const Key('remove-move-note'),
                style: theme.textTheme.bodySmall!.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ],
          ],
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('remove-go'),
          onPressed: !ready
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  switch (_choice!) {
                    case _RemoveChoice.hide:
                      navigator.pop(const RemoveHide());
                    case _RemoveChoice.move:
                      navigator.pop(RemoveMove(_to!));
                    case _RemoveChoice.delete:
                      final yes = await confirmDelete(
                        context,
                        title: AccountEditText.deleteQuestion(
                          account.name,
                          count,
                        ),
                        body: AccountEditText.deleteBody(
                          money(held, unit: true),
                          count,
                        ),
                      );
                      if (yes) navigator.pop(const RemoveDelete());
                  }
                },
          child: Text(button ?? AccountEditText.remove(account.name)),
        ),
      ],
    );
  }
}
