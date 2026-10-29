import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../domain/debts/debt.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/selector_field.dart';
import '../../goals/application/goals_overview_provider.dart';
import '../application/debts_overview_provider.dart';

/// How each kind of debt reads on screen.
String debtTypeLabel(DebtType type) => switch (type) {
  DebtType.bankLoan => 'Bank loan',
  DebtType.card => 'Credit card',
  DebtType.overdraft => 'Overdraft',
  DebtType.salaryAdvance => 'Salary advance',
  DebtType.fuliza => 'Fuliza',
  DebtType.mobileLoan => 'Mobile loan',
  DebtType.saccoLoan => 'Sacco loan',
  DebtType.family => 'Family or friend',
};

/// Opens the sheet to add a debt, or to edit or pay [debt].
Future<void> showDebtSheet(
  BuildContext context, {
  required CalendarDate today,
  Debt? debt,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => DebtSheet(today: today, debt: debt),
);

/// Reloads everything that reads debts after a change.
void refreshDebts(ProviderContainer container) {
  container
    ..invalidate(debtPreferenceProvider)
    ..invalidate(debtsOverviewProvider);
  refreshGoals(container);
}

/// Who is owed, how much, the rate and the monthly minimum.
class DebtSheet extends StatefulWidget {
  const DebtSheet({required this.today, this.debt, super.key});

  final CalendarDate today;

  /// The debt to edit; null to add one.
  final Debt? debt;

  @override
  State<DebtSheet> createState() => _DebtSheetState();
}

class _DebtSheetState extends State<DebtSheet> {
  final _form = GlobalKey<FormState>();
  late var _type = widget.debt?.type ?? DebtType.bankLoan;
  late final _lender = TextEditingController(text: widget.debt?.lender);
  late final _balance = TextEditingController(
    text: _amountText(widget.debt?.balanceMinor),
  );
  late final _rate = TextEditingController(
    text: _rateText(widget.debt?.annualRateBasisPoints),
  );
  late final _minimum = TextEditingController(
    text: _amountText(widget.debt?.minimumPaymentMinor),
  );
  late final _payment = TextEditingController();
  var _busy = false;

  bool get _editing => widget.debt != null;
  bool get _family => _type == DebtType.family;

  @override
  void dispose() {
    _lender.dispose();
    _balance.dispose();
    _rate.dispose();
    _minimum.dispose();
    _payment.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final debts = container.read(debtsRepositoryProvider);
    final balance = AmountField.amountFrom(_balance.text)!;
    final rate = _family ? null : _rateFrom(_rate.text);
    final minimum = AmountField.amountFrom(_minimum.text) ?? 0;
    final details = DebtsCompanion(
      lender: Value(_lender.text.trim()),
      type: Value(_type),
      annualRateBasisPoints: Value(rate == 0 ? null : rate),
      minimumPaymentMinor: Value(minimum),
      isFormal: Value(!_family),
    );

    final existing = widget.debt;
    if (existing == null) {
      await debts.add(details.copyWith(startingBalanceMinor: Value(balance)));
    } else {
      await debts.update(existing.id, details);
      if (balance != existing.balanceMinor) {
        await debts.confirmBalance(
          existing.id,
          balance,
          widget.today.startInstant,
        );
      }
    }
    refreshDebts(container);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _recordPayment() async {
    final amount = AmountField.amountFrom(_payment.text);
    if (amount == null || amount == 0) return;
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    await container
        .read(debtsRepositoryProvider)
        .recordPayment(
          widget.debt!.id,
          container.read(clockProvider)(),
          amount,
        );
    refreshDebts(container);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final debt = widget.debt!;
    final sure = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text('Remove ${debt.lender}?'),
        content: const Text(
          'Its payments stay in Activity and go back to being plain '
          'spending.',
        ),
        actions: [
          DialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          DialogAction(
            destructive: true,
            filled: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(debtsRepositoryProvider).remove(debt.id);
    refreshDebts(container);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _editing ? widget.debt!.lender : 'Add a debt',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              // A fixed set of eight: shown in full, nothing to search.
              SelectorField(
                label: 'Kind of debt',
                value: debtTypeLabel(_type),
                onTap: () async {
                  final type = await showOptionSheet<DebtType>(
                    context,
                    title: 'Kind of debt',
                    options: [
                      for (final type in DebtType.values)
                        (type, debtTypeLabel(type)),
                    ],
                    selected: _type,
                  );
                  if (type != null) setState(() => _type = type);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lender,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: _family ? 'Who lent it' : 'Lender',
                ),
                inputFormatters: [LengthLimitingTextInputFormatter(80)],
                validator: (text) => (text ?? '').trim().isEmpty
                    ? 'Add a name, such as KCB or Mama.'
                    : null,
              ),
              const SizedBox(height: 12),
              AmountField(
                controller: _balance,
                label: _editing ? 'Owed today' : 'Owed now',
                allowZero: _editing,
              ),
              if (!_family) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Interest a year',
                    suffixText: '%',
                    helperText: 'Leave empty for an interest-free loan.',
                  ),
                  validator: (text) => _rateFrom(text ?? '') == null
                      ? 'Enter a rate, such as 13 or 12.5.'
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              AmountField(
                controller: _minimum,
                label: _family ? 'Agreed each month' : 'Minimum each month',
                allowZero: true,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_editing ? 'Save changes' : 'Add debt'),
              ),
              if (_editing) ...[
                const SizedBox(height: 24),
                Text('Paid by hand?', style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Payments in your messages count on their own. Add cash '
                  'or anything a message missed here.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                AmountField(
                  controller: _payment,
                  label: 'Payment',
                  allowZero: true,
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _recordPayment,
                  child: const Text('Record payment'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _busy ? null : _remove,
                  child: const Text('Remove this debt'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _amountText(int? minor) => minor == null || minor == 0
    ? ''
    : formatMoney(Money(minor), withCurrency: false);

String _rateText(int? basisPoints) {
  if (basisPoints == null || basisPoints == 0) return '';
  final whole = basisPoints ~/ 100;
  final hundredths = basisPoints % 100;
  if (hundredths == 0) return '$whole';
  return '$whole.${hundredths.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '')}';
}

/// A yearly rate in basis points: 0 for an empty field, null when it is not
/// a rate.
int? _rateFrom(String text) {
  final clean = text.trim().replaceAll('%', '');
  if (clean.isEmpty) return 0;
  final match = RegExp(r'^(\d{1,3})(?:\.(\d{1,2}))?$').firstMatch(clean);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction);
}
