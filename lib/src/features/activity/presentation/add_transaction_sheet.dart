import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/selector_field.dart';
import '../../currency/application/currency_controller.dart';
import '../../payees/presentation/category_picker.dart';
import '../application/activity_providers.dart';

/// Opens the sheet for adding a transaction by hand.
Future<void> showAddTransactionSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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
  final _amount = TextEditingController();
  final _name = TextEditingController();
  var _direction = TransactionDirection.outflow;
  int? _accountId;
  int? _categoryId;
  CalendarDate? _date;
  String? _amountError;
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
    final currency = _currency(accounts);
    final amount = parseMoneyMinor(_amount.text, currency: currency);
    if (amount == null) {
      setState(() => _amountError = 'Enter an amount, such as 1,250');
      return;
    }
    setState(() {
      _amountError = null;
      _saving = true;
    });

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

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a transaction', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
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
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Amount ($currency)',
                errorText: _amountError,
                helperText: inBase == null
                    ? null
                    : '≈ ${formatMoney(Money(inBase.baseMinor, currency: base))} '
                          "at today's rate",
              ),
            ),
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
              SelectorField(
                label: 'Account',
                value: accountLabel(
                  accounts[_accountId ?? accounts.keys.first]!,
                ),
                onTap: () async {
                  final id = await showOptionSheet<int>(
                    context,
                    title: 'Account',
                    options: [
                      for (final a in accounts.values) (a.id, accountLabel(a)),
                    ],
                    selected: _accountId ?? accounts.keys.first,
                  );
                  if (id != null) setState(() => _accountId = id);
                },
              ),
            ],
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(dayHeading(date, today: today)),
              subtitle: const Text('Tap to change the day'),
              onTap: () async {
                final picked = await pickDate(
                  context,
                  initialDate: DateTime(date.year, date.month, date.day),
                  firstDate: DateTime(today.year - 2),
                  lastDate: DateTime(today.year, today.month, today.day),
                );
                if (picked != null) {
                  setState(
                    () => _date = CalendarDate(
                      picked.year,
                      picked.month,
                      picked.day,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : () => _save(today, accounts),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
