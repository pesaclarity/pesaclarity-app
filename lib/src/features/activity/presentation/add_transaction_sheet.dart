import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/selector_field.dart';
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

/// Parses a typed amount such as `1,250` or `99.50` into minor units; null
/// when it is not a positive amount.
int? parseAmountMinor(String text) {
  final cleaned = text.replaceAll(',', '').trim();
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) return null;
  final major = int.parse(match[1]!);
  final minor = int.parse((match[2] ?? '0').padRight(2, '0'));
  final total = major * 100 + minor;
  return total > 0 ? total : null;
}

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

  Future<void> _save(CalendarDate today, Map<int, Account> accounts) async {
    final amount = parseAmountMinor(_amount.text);
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
            currency: Value(BaseCurrency.code),
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
              decoration: InputDecoration(
                labelText: 'Amount (${BaseCurrency.code})',
                errorText: _amountError,
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
                value: accounts[_accountId ?? accounts.keys.first]!.name,
                onTap: () async {
                  final id = await showOptionSheet<int>(
                    context,
                    title: 'Account',
                    options: [for (final a in accounts.values) (a.id, a.name)],
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
