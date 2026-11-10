import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/repositories/plan_repository.dart';
import '../../../domain/plan/month_plan.dart';
import '../../../domain/plan/plan_inputs.dart' as plan;
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../theme/pesa_colors.dart';
import '../../debts/presentation/debts_screen.dart' show monthLabel;
import '../../payees/presentation/category_picker.dart';
import '../application/plan_providers.dart';

/// Opens the form to add a bill, income or one-off to [month], or to edit
/// [line].
Future<void> showPlanItemSheet(
  BuildContext context, {
  required YearMonth month,
  PlanLine? line,
}) async {
  final container = ProviderScope.containerOf(context);
  plan.RecurringBill? bill;
  if (line?.source == PlanLineSource.recurring && line?.sourceId != null) {
    bill = await container
        .read(planRepositoryProvider)
        .recurringBill(line!.sourceId!);
    if (bill == null) return;
  }
  if (!context.mounted) return;
  await showAppSheet<void>(
    context: context,
    builder: (context) => PlanItemForm(month: month, line: line, bill: bill),
  );
}

enum _Kind { repeats, oneOff }

const _frequencyLabels = {
  RecurrenceFrequency.weekly: 'Every week',
  RecurrenceFrequency.monthly: 'Every month',
  RecurrenceFrequency.quarterly: 'Every three months',
  RecurrenceFrequency.yearly: 'Every year',
};

/// Add or edit one plan item: a recurring bill or income, a one-off, or a
/// carried-forward arrear.
class PlanItemForm extends ConsumerStatefulWidget {
  const PlanItemForm({required this.month, this.line, this.bill, super.key});

  final YearMonth month;

  /// The line being edited; null when adding.
  final PlanLine? line;

  /// The recurring bill behind [line], when it is one.
  final plan.RecurringBill? bill;

  @override
  ConsumerState<PlanItemForm> createState() => _PlanItemFormState();
}

class _PlanItemFormState extends ConsumerState<PlanItemForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late _Kind _kind;
  int? _categoryId;
  RecurrenceFrequency _frequency = RecurrenceFrequency.monthly;
  late CalendarDate _startDate;
  bool _paid = false;
  bool _saving = false;

  bool get _isEditing => widget.line != null;

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    final bill = widget.bill;
    _name = TextEditingController(text: bill?.name ?? line?.name ?? '');
    final amount = bill?.amountMinor ?? line?.amountMinor;
    _amount = TextEditingController(
      text: amount == null
          ? ''
          : formatMoney(Money(amount), withCurrency: false),
    );
    _kind = line == null || line.source == PlanLineSource.recurring
        ? _Kind.repeats
        : _Kind.oneOff;
    _categoryId = bill?.categoryId ?? line?.categoryId;
    _frequency = bill?.frequency ?? RecurrenceFrequency.monthly;
    _paid = line?.isMarkedPaid ?? false;
    final today = CalendarDate.local(ref.read(clockProvider)());
    _startDate =
        bill?.startDate ??
        (widget.month.contains(today) ? today : widget.month.firstDay);
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories =
        ref.watch(planCategoriesProvider).value ?? const <Category>[];
    final line = widget.line;
    final title = switch (line?.source) {
      null => 'Add to ${monthLabel(widget.month)}',
      PlanLineSource.recurring => 'Edit repeating item',
      PlanLineSource.oneOff => 'Edit one-off',
      PlanLineSource.arrears => 'Edit carried-forward bill',
    };

    return Form(
      key: _formKey,
      child: SheetBody(
        title: title,
        children: [
          if (!_isEditing) ...[
            AdaptiveSegmented<_Kind>(
              segments: const [
                (_Kind.repeats, 'Repeats'),
                (_Kind.oneOff, 'One-off'),
              ],
              selected: _kind,
              onChanged: (value) => setState(() => _kind = value),
            ),
            const SizedBox(height: 16),
          ],
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.sentences,
            maxLength: 80,
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter a name, such as Rent.' : null,
          ),
          const SizedBox(height: 8),
          AmountField(controller: _amount, label: 'Amount'),
          const SizedBox(height: 16),
          CategorySelectorField(
            key: const Key('plan-item-category'),
            selectedId: categories.any((c) => c.id == _categoryId)
                ? _categoryId
                : null,
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 16),
          if (_kind == _Kind.repeats) ...[
            Text(
              'How often',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: PesaColors.of(context).textMuted,
              ),
            ),
            const SizedBox(height: 8),
            ChoiceMenu<RecurrenceFrequency>(
              key: const Key('plan-item-frequency'),
              name: 'How often',
              expand: true,
              options: [
                for (final MapEntry(:key, :value) in _frequencyLabels.entries)
                  (key, value),
              ],
              value: _frequency,
              onChanged: (value) => setState(() => _frequency = value),
            ),
            const SizedBox(height: 16),
            DateField(
              label: 'First due date',
              value: _startDate,
              firstDate: CalendarDate(2000, 1, 1),
              lastDate: CalendarDate(2100, 12, 31),
              onChanged: (date) {
                if (date != null) setState(() => _startDate = date);
              },
            ),
          ] else
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Paid'),
              subtitle: const Text('Mark it paid, such as in cash.'),
              value: _paid,
              onChanged: (v) => setState(() => _paid = v),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
          if (_isEditing) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _saving ? null : _delete,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(switch (line?.source) {
                PlanLineSource.recurring => 'Delete repeating item',
                PlanLineSource.arrears => 'Delete carried-forward bill',
                _ => 'Delete one-off',
              }),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repository = ref.read(planRepositoryProvider);
    final name = _name.text.trim();
    final amount = AmountField.amountFrom(_amount.text)!;
    final line = widget.line;

    if (_kind == _Kind.repeats) {
      await repository.saveRecurring(
        id: widget.bill?.id,
        name: name,
        categoryId: _categoryId,
        amountMinor: amount,
        frequency: _frequency,
        startDate: _startDate,
        endDate: widget.bill?.endDate,
      );
    } else {
      await repository.saveBudgetItem(
        plan.BudgetItem(
          id: line?.sourceId,
          month: widget.month,
          name: name,
          categoryId: _categoryId,
          amountMinor: amount,
          kind: line?.source == PlanLineSource.arrears
              ? BudgetItemKind.carriedArrears
              : BudgetItemKind.oneOff,
          isPaid: _paid,
        ),
      );
    }
    _done();
  }

  Future<void> _delete() async {
    final line = widget.line!;
    final recurring = line.source == PlanLineSource.recurring;
    final confirmed = await confirmDelete(
      context,
      title: 'Delete ${line.name}?',
      body: recurring
          ? 'It leaves ${monthLabel(widget.month)} and later months. '
                'Earlier months keep it.'
          : 'It leaves ${monthLabel(widget.month)}.',
    );
    if (!confirmed) return;
    setState(() => _saving = true);
    final repository = ref.read(planRepositoryProvider);
    final id = line.sourceId!;
    if (recurring) {
      await repository.stopRecurring(id, from: widget.month);
    } else {
      await repository.deleteBudgetItem(id);
    }
    _done();
  }

  void _done() {
    refreshPlan(ref);
    if (mounted) Navigator.of(context).pop();
  }
}
