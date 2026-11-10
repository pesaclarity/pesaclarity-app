import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../theme/pesa_colors.dart';
import '../../currency/application/currency_controller.dart';
import '../../payees/presentation/category_picker.dart';
import '../application/activity_providers.dart';

/// Opens the sheet for adding a transaction by hand.
Future<void> showAddTransactionSheet(BuildContext context) =>
    showAppSheet<void>(
      context: context,
      builder: (context) => const AddTransactionSheet(),
    );

/// Name of the account made for hand-added money when there is none yet.
const cashAccountName = 'Cash';

/// A form for cash spending, or anything the messages missed.
class AddTransactionSheet extends ConsumerStatefulWidget {
  const AddTransactionSheet({super.key});

  @override
  ConsumerState<AddTransactionSheet> createState() =>
      _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<AddTransactionSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _name = TextEditingController();
  var _direction = TransactionDirection.outflow;
  int? _accountId;
  int? _categoryId;
  CalendarDate? _date;
  var _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _name.dispose();
    super.dispose();
  }

  /// The currency of the account the money is in: the base currency for
  /// the cash account made when there is none.
  String _currency(Map<int, Account> accounts) {
    final id = _accountId ?? accounts.keys.firstOrNull;
    return accounts[id]?.currency ?? ref.read(baseCurrencyProvider);
  }

  Future<void> _save(CalendarDate today, Map<int, Account> accounts) async {
    if (!_form.currentState!.validate()) return;
    final currency = _currency(accounts);
    // The field has checked it reads in the account's currency.
    final amount = parseMoneyMinor(_amount.text, currency: currency)!;
    setState(() => _saving = true);

    final now = ref.read(clockProvider)();
    final date = _date ?? today;
    var accountId = _accountId ?? accounts.keys.firstOrNull;
    accountId ??= await ref
        .read(accountsRepositoryProvider)
        .add(
          AccountsCompanion.insert(
            name: cashAccountName,
            type: AccountType.cash,
            currency: Value(currency),
            openingDate: today.startInstant,
          ),
        );
    final name = _name.text.trim();
    await ref
        .read(transactionsRepositoryProvider)
        .add(
          TransactionsCompanion.insert(
            accountId: accountId,
            // A past day is placed at noon so it lands on that Nairobi day.
            occurredAt: date == today
                ? now
                : date.startInstant.add(const Duration(hours: 12)),
            amountMinor: amount,
            // The account's currency: an M-Pesa payment is in KES whatever
            // the base currency.
            currency: Value(currency),
            direction: _direction,
            source: TransactionSource.manual,
            counterpartyName: Value(name.isEmpty ? null : name),
            categoryOverrideId: Value(_categoryId),
          ),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final accounts = ref.watch(activityAccountsProvider).value ?? const {};
    final date = _date ?? today;
    final base = ref.watch(baseCurrencyProvider);
    final currency = _currency(accounts);
    final typed = parseMoneyMinor(_amount.text, currency: currency);
    final inBase = typed == null || currency == base
        ? null
        : ref
              .watch(currencyConverterProvider)
              .convert(typed, currency, ref.read(clockProvider)());
    // Accounts in more than one currency show theirs.
    final mixed = accounts.values.map((a) => a.currency).toSet().length > 1;
    String accountLabel(Account a) =>
        mixed ? '${a.name} · ${a.currency}' : a.name;

    final muted = theme.textTheme.bodyMedium!.copyWith(
      color: PesaColors.of(context).textMuted,
    );

    return Form(
      key: _form,
      child: SheetBody(
        title: 'Add a transaction',
        children: [
          AdaptiveSegmented<TransactionDirection>(
            segments: const [
              (TransactionDirection.outflow, 'Money out'),
              (TransactionDirection.inflow, 'Money in'),
            ],
            selected: _direction,
            onChanged: (value) => setState(() {
              _direction = value;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 16),
          AmountField(
            key: const Key('add-transaction-amount'),
            controller: _amount,
            label: 'Amount',
            currency: currency,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          if (inBase != null) ...[
            const SizedBox(height: 4),
            Text(
              '≈ ${formatMoney(Money(inBase.baseMinor, currency: base))} '
              "at today's rate",
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: _direction == TransactionDirection.outflow
                  ? 'Paid to'
                  : 'Received from',
            ),
          ),
          const SizedBox(height: 12),
          CategorySelectorField(
            key: const Key('add-transaction-category'),
            selectedId: _categoryId,
            allowType: (type) => _direction == TransactionDirection.inflow
                ? type != CategoryType.expense
                : type != CategoryType.income,
            onChanged: (id) => setState(() => _categoryId = id),
          ),
          if (accounts.length > 1) ...[
            const SizedBox(height: 12),
            Text('Account', style: muted),
            const SizedBox(height: 4),
            ChoiceMenu<int>(
              key: const Key('add-transaction-account'),
              name: 'Account',
              expand: true,
              options: [
                for (final a in accounts.values) (a.id, accountLabel(a)),
              ],
              value: _accountId ?? accounts.keys.first,
              onChanged: (id) => setState(() => _accountId = id),
            ),
          ],
          const SizedBox(height: 12),
          DateField(
            key: const Key('add-transaction-date'),
            label: 'Date',
            value: date,
            firstDate: CalendarDate(today.year - 2, 1, 1),
            lastDate: today,
            onChanged: (picked) => setState(() => _date = picked),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : () => _save(today, accounts),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
