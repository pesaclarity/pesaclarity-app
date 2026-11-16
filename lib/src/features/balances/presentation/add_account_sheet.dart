import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/balances_repository.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../currency/application/currency_controller.dart';
import '../../currency/presentation/currency_picker.dart';
import 'balance_text.dart';

/// The kinds of account a person adds by hand, in menu order.
const addableAccountTypes = [
  AccountType.cash,
  AccountType.bank,
  AccountType.mpesa,
  AccountType.sacco,
  AccountType.other,
];

/// Adds cash, or any account whose messages the app does not read.
Future<void> showAddAccountSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  builder: (context) => const AddAccountSheet(),
);

class AddAccountSheet extends ConsumerStatefulWidget {
  const AddAccountSheet({super.key});

  @override
  ConsumerState<AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends ConsumerState<AddAccountSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(text: 'Cash');
  final _balance = TextEditingController();
  var _type = AccountType.cash;
  String? _currency;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }

  Future<void> _pickCurrency(String current) async {
    final picked = await showAppSheet<String>(
      context: context,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: CurrencyPicker(
          selected: current,
          onSelected: (code) => Navigator.pop(context, code),
        ),
      ),
    );
    if (picked != null) setState(() => _currency = picked);
  }

  Future<void> _save(String currency) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final name = _name.text.trim();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await ref
        .read(balancesRepositoryProvider)
        .addAccount(
          name: name,
          type: _type,
          currency: currency,
          balanceMinor:
              AmountField.amountFrom(_balance.text, currency: currency) ?? 0,
          at: ref.read(clockProvider)(),
        );
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(BalanceText.accountAdded(name))));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium!.copyWith(
      color: PesaColors.of(context).textMuted,
    );
    final String currency = _currency ?? ref.watch(baseCurrencyProvider);
    return Form(
      key: _form,
      child: SheetBody(
        title: BalanceText.addAccount,
        subtitle: BalanceText.addAccountIntro,
        children: [
          TextFormField(
            key: const Key('add-account-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: BalanceText.accountName,
            ),
            validator: (text) => (text ?? '').trim().isEmpty
                ? 'Give it a name, such as Cash.'
                : null,
          ),
          const SizedBox(height: Layout.cardGap),
          Text(BalanceText.accountType, style: muted),
          const SizedBox(height: 4),
          ChoiceMenu<AccountType>(
            key: const Key('add-account-type'),
            name: BalanceText.accountType,
            expand: true,
            options: [
              for (final t in addableAccountTypes)
                (t, BalanceText.typeLabel(t)),
            ],
            value: _type,
            onChanged: (type) => setState(() {
              // Keep a typed name; swap the suggested one.
              final suggested = addableAccountTypes
                  .map(BalanceText.typeLabel)
                  .contains(_name.text.trim());
              if (suggested || _name.text.trim().isEmpty) {
                _name.text = BalanceText.typeLabel(type);
              }
              _type = type;
            }),
          ),
          const SizedBox(height: Layout.cardGap),
          ListTile(
            key: const Key('add-account-currency'),
            contentPadding: EdgeInsets.zero,
            title: const Text(BalanceText.currency),
            subtitle: Text(currency),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _pickCurrency(currency),
          ),
          AmountField(
            key: const Key('add-account-balance'),
            controller: _balance,
            label: BalanceText.currentBalance,
            currency: currency,
            allowZero: true,
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('add-account-save'),
            onPressed: _saving ? null : () => _save(currency),
            child: const Text(BalanceText.addAccountSave),
          ),
        ],
      ),
    );
  }
}
