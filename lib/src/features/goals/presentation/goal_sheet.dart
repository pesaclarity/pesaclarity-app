import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/goals_repository.dart';
import '../../../domain/goals/savings_goal.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/widgets/form_fields.dart';
import '../application/goals_overview_provider.dart';

/// Opens the sheet to add a goal, or to edit or delete [goal].
Future<void> showGoalSheet(
  BuildContext context, {
  required CalendarDate today,
  SavingsGoal? goal,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => GoalSheet(today: today, goal: goal),
);

/// Name, target, what is saved so far and an optional date for a goal.
class GoalSheet extends StatefulWidget {
  const GoalSheet({required this.today, this.goal, super.key});

  final CalendarDate today;

  /// The goal to edit; null to add one.
  final SavingsGoal? goal;

  @override
  State<GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<GoalSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.goal?.name);
  late final _target = TextEditingController(
    text: _amountText(widget.goal?.targetMinor),
  );
  late final _saved = TextEditingController(
    text: _amountText(widget.goal?.savedMinor),
  );
  late CalendarDate? _date = widget.goal?.targetDate;
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _saved.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = container.read(goalsRepositoryProvider);
    final name = _name.text.trim();
    final target = AmountField.amountFrom(_target.text)!;
    final saved = AmountField.amountFrom(_saved.text) ?? 0;
    final existing = widget.goal;
    if (existing == null) {
      await repository.add(
        name: name,
        targetMinor: target,
        savedMinor: saved,
        targetDate: _date,
      );
    } else {
      await repository.update(
        SavingsGoal(
          id: existing.id,
          name: name,
          targetMinor: target,
          savedMinor: saved,
          targetDate: _date,
          currency: existing.currency,
          status: existing.status,
        ),
      );
    }
    refreshGoals(container);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final goal = widget.goal!;
    final container = ProviderScope.containerOf(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${goal.name}?'),
        content: const Text('The goal and its saved amount are removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await container.read(goalsRepositoryProvider).remove(goal.id);
    refreshGoals(container);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.goal != null;
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                editing ? 'Edit goal' : 'Add a goal',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'What are you saving for?',
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                validator: (text) => (text ?? '').trim().isEmpty
                    ? 'Give the goal a name.'
                    : null,
              ),
              const SizedBox(height: 8),
              AmountField(controller: _target, label: 'Target'),
              const SizedBox(height: 16),
              AmountField(
                controller: _saved,
                label: 'Saved so far',
                allowZero: true,
              ),
              const SizedBox(height: 16),
              DateField(
                label: 'Target date (optional)',
                value: _date,
                clearable: true,
                firstDate: widget.today,
                lastDate: CalendarDate(widget.today.year + 30, 12, 31),
                onChanged: (date) => setState(() => _date = date),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(editing ? 'Save' : 'Add goal'),
              ),
              if (editing) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy ? null : _delete,
                  child: const Text('Delete goal'),
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
