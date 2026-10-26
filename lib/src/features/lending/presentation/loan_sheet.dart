import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/debts_repository.dart';
import '../../../data/repositories/lending_repository.dart';
import '../../../domain/debts/debt.dart';
import '../../../domain/lending/lent_loan.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../goals/application/goals_overview_provider.dart';

/// Which way the money went.
enum LoanSide { lent, borrowed }

/// Opens the sheet to record money lent or borrowed, or to edit [lent].
Future<void> showLoanSheet(
  BuildContext context, {
  required CalendarDate today,
  LentLoan? lent,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => LoanSheet(today: today, lent: lent),
);

/// Who, how much, when, and when it is due back.
class LoanSheet extends StatefulWidget {
  const LoanSheet({required this.today, this.lent, super.key});

  final CalendarDate today;

  /// Money lent to edit; null to add a loan on either side.
  final LentLoan? lent;

  @override
  State<LoanSheet> createState() => _LoanSheetState();
}

class _LoanSheetState extends State<LoanSheet> {
  final _form = GlobalKey<FormState>();
  late var _side = LoanSide.lent;
  late final _person = TextEditingController(text: widget.lent?.person);
  late final _amount = TextEditingController(
    text: widget.lent == null
        ? ''
        : formatMoney(Money(widget.lent!.amountMinor), withCurrency: false),
  );
  late final _note = TextEditingController(text: widget.lent?.note);
  late CalendarDate _on = widget.lent?.lentOn ?? widget.today;
  late CalendarDate? _due = widget.lent?.dueDate;
  var _busy = false;

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final person = _person.text.trim();
    final amount = AmountField.amountFrom(_amount.text)!;
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final existing = widget.lent;

    if (existing != null) {
      await container
          .read(lendingRepositoryProvider)
          .update(
            LentLoan(
              id: existing.id,
              person: person,
              amountMinor: amount,
              lentOn: _on,
              dueDate: _due,
              note: note,
              currency: existing.currency,
              payments: existing.payments,
            ),
          );
    } else if (_side == LoanSide.lent) {
      await container
          .read(lendingRepositoryProvider)
          .add(
            person: person,
            amountMinor: amount,
            lentOn: _on,
            dueDate: _due,
            note: note,
          );
    } else {
      final debts = container.read(debtsRepositoryProvider);
      final id = await debts.add(
        DebtsCompanion.insert(
          lender: person,
          type: DebtType.family,
          startingBalanceMinor: amount,
          isFormal: const Value(false),
        ),
      );
      if (_due case final due?) {
        await debts.setInstalments(id, [
          DebtInstalment(dueDate: due, amountMinor: amount),
        ]);
      }
    }
    refreshGoals(container);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.lent != null;
    final lent = _side == LoanSide.lent;
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
                editing ? 'Edit loan' : 'Add a loan',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (!editing) ...[
                SegmentedButton<LoanSide>(
                  segments: const [
                    ButtonSegment(value: LoanSide.lent, label: Text('I lent')),
                    ButtonSegment(
                      value: LoanSide.borrowed,
                      label: Text('I borrowed'),
                    ),
                  ],
                  selected: {_side},
                  onSelectionChanged: (s) => setState(() => _side = s.first),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _person,
                decoration: InputDecoration(
                  labelText: lent ? 'Lent to' : 'Borrowed from',
                ),
                textCapitalization: TextCapitalization.words,
                maxLength: 80,
                validator: (text) =>
                    (text ?? '').trim().isEmpty ? 'Add a name.' : null,
              ),
              const SizedBox(height: 8),
              AmountField(controller: _amount, label: 'Amount'),
              const SizedBox(height: 16),
              if (lent) ...[
                DateField(
                  label: 'Lent on',
                  value: _on,
                  firstDate: CalendarDate(widget.today.year - 10, 1, 1),
                  lastDate: widget.today,
                  onChanged: (date) =>
                      setState(() => _on = date ?? widget.today),
                ),
                const SizedBox(height: 16),
              ],
              DateField(
                label: 'Due back (optional)',
                value: _due,
                clearable: true,
                firstDate: lent ? _on : widget.today,
                lastDate: CalendarDate(widget.today.year + 10, 12, 31),
                onChanged: (date) => setState(() => _due = date),
              ),
              if (lent) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                  maxLength: 120,
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'It joins your debts, interest-free, so the payoff plan '
                  'counts it.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(editing ? 'Save' : 'Add'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the sheet to record a part payment on a loan with [remainingMinor]
/// left. [onSave] gets the amount and when it was paid.
Future<void> showPaymentSheet(
  BuildContext context, {
  required String person,
  required int remainingMinor,
  required CalendarDate firstDate,
  required CalendarDate today,
  required DateTime now,
  required Future<void> Function(int amountMinor, DateTime paidAt) onSave,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => PaymentSheet(
    person: person,
    remainingMinor: remainingMinor,
    firstDate: firstDate,
    today: today,
    now: now,
    onSave: onSave,
  ),
);

/// A part payment: how much and on which day.
class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    required this.person,
    required this.remainingMinor,
    required this.firstDate,
    required this.today,
    required this.now,
    required this.onSave,
    super.key,
  });

  final String person;
  final int remainingMinor;
  final CalendarDate firstDate;
  final CalendarDate today;
  final DateTime now;
  final Future<void> Function(int amountMinor, DateTime paidAt) onSave;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late CalendarDate _on = widget.today;
  var _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    // Today's payment keeps the time, so it lands after a balance confirmed
    // earlier today.
    final paidAt = _on == widget.today ? widget.now : _on.startInstant;
    await widget.onSave(AmountField.amountFrom(_amount.text)!, paidAt);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Payment, ${widget.person}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '${formatMoney(Money(widget.remainingMinor))} left.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            AmountField(
              controller: _amount,
              label: 'Amount paid',
              maxMinor: widget.remainingMinor,
            ),
            const SizedBox(height: 16),
            DateField(
              label: 'Paid on',
              value: _on,
              firstDate: widget.firstDate,
              lastDate: widget.today,
              onChanged: (date) => setState(() => _on = date ?? widget.today),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Record payment'),
            ),
          ],
        ),
      ),
    );
  }
}
