import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/goals_repository.dart';
import '../../../domain/goals/savings_goal.dart';
import '../../../domain/savings/savings_account.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/selector_field.dart';
import '../../currency/application/currency_controller.dart';
import '../../savings/application/savings_providers.dart';
import '../../savings/presentation/savings_text.dart';
import '../application/goals_aside_providers.dart';
import '../application/goals_overview_provider.dart';
import 'goals_aside_text.dart';

/// Opens the sheet to add a goal, or to edit or delete [goal].
Future<void> showGoalSheet(
  BuildContext context, {
  required CalendarDate today,
  SavingsGoal? goal,
}) => showAppSheet<void>(
  context: context,
  builder: (context) => GoalSheet(today: today, goal: goal),
);

/// Name, target, what is saved so far and an optional date for a goal.
class GoalSheet extends ConsumerStatefulWidget {
  const GoalSheet({required this.today, this.goal, super.key});

  final CalendarDate today;

  /// The goal to edit; null to add one.
  final SavingsGoal? goal;

  @override
  ConsumerState<GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<GoalSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.goal?.name);
  late final _target = TextEditingController(
    text: _amountText(widget.goal?.targetMinor),
  );
  late final _saved = TextEditingController(
    text: _amountText(widget.goal?.savedMinor),
  );
  late CalendarDate? _date = widget.goal?.targetDate;

  /// The savings app's goal the money is kept in, such as a Chumz goal;
  /// null when the person types what is saved.
  late int? _pocketId = widget.goal?.backing?.pocketId;

  /// "Keep it aside" as switched here; null until the person touches it,
  /// when the saved setting shows.
  bool? _keep;
  var _busy = false;

  bool get _kept =>
      _keep ??
      (widget.goal != null &&
          (ref.read(keptAsideProvider).value?.isKept(widget.goal!.id) ??
              false));

  /// Whether the goal can be kept aside: its saved amount is typed, in the
  /// base currency. A savings app's goal is already out of On hand.
  bool get _canKeepAside =>
      _pocketId == null &&
      (widget.goal?.currency ?? ref.read(baseCurrencyProvider)) ==
          ref.read(baseCurrencyProvider);

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
    final int goalId;
    if (existing == null) {
      goalId = await repository.add(
        name: name,
        targetMinor: target,
        savedMinor: saved,
        targetDate: _date,
      );
    } else {
      goalId = existing.id;
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
    if (_pocketId != existing?.backing?.pocketId) {
      await repository.setPocket(goalId, _pocketId);
    }
    final kept = container.read(keptAsideProvider.notifier);
    final keep = _canKeepAside && _kept;
    await kept.setKept(goalId, kept: keep);
    // A new saved amount starts afresh after a dip that was left as it is.
    if (keep && existing != null && saved != existing.savedMinor) {
      await kept.savedChanged(goalId);
    }
    refreshGoals(container);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final goal = widget.goal!;
    final container = ProviderScope.containerOf(context, listen: false);
    final confirmed = await confirmDelete(
      context,
      title: 'Delete ${goal.name}?',
      body: 'The goal and its saved amount are removed.',
    );
    if (!confirmed) return;
    await container.read(goalsRepositoryProvider).remove(goal.id);
    refreshGoals(container);
    if (mounted) Navigator.of(context).pop();
  }

  /// "Saved in": nowhere, or one goal of a savings app the app keeps, in
  /// the goal's currency. Null when there is none to choose.
  Widget? _savedIn() {
    final currency = widget.goal?.currency ?? ref.watch(baseCurrencyProvider);
    // The option sheet answers null when dismissed, so "nowhere" is -1.
    const nowhere = -1;
    final options = <(int, String)>[
      (nowhere, SavingsText.typedByYou),
      for (final account
          in ref.watch(savingsAccountsProvider).value ??
              const <SavingsAccountSummary>[])
        if (account.currency == currency)
          for (final pocket in account.pockets)
            (pocket.id, '${account.name} · ${pocket.name}'),
    ];
    if (options.length == 1) return null;
    final selected = _pocketId ?? nowhere;
    final chosen = options.where((o) => o.$1 == selected).firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SelectorField(
        key: const Key('goal-saved-in'),
        label: SavingsText.savedInLabel,
        value: chosen?.$2 ?? SavingsText.typedByYou,
        detail: selected == nowhere ? SavingsText.typedByYouDetail : null,
        onTap: () async {
          final picked = await showOptionSheet<int>(
            context,
            title: SavingsText.savedInLabel,
            options: options,
            selected: selected,
          );
          if (picked == null || !mounted) return;
          setState(() => _pocketId = picked == nowhere ? null : picked);
        },
      ),
    );
  }

  /// The "Keep it aside" switch, and while it is on, a plain note that
  /// this is not a bank lock.
  List<Widget> _keepAside(BuildContext context) {
    // Rebuilds once the saved setting has loaded.
    ref.watch(keptAsideProvider);
    final keep = _kept;
    return [
      const SizedBox(height: 12),
      ValueListenableBuilder(
        valueListenable: _saved,
        builder: (context, value, _) {
          final saved = AmountField.amountFrom(value.text) ?? 0;
          return SwitchListTile.adaptive(
            key: const Key('goal-keep-aside'),
            contentPadding: EdgeInsets.zero,
            title: const Text(GoalsAsideText.keepItAside),
            subtitle: Text(
              GoalsAsideText.keepItAsideDetail(
                saved <= 0 || _pocketId != null
                    ? null
                    : shownMoney(context, saved),
              ),
            ),
            value: keep,
            onChanged: (on) => setState(() => _keep = on),
          );
        },
      ),
      if (keep) ...[
        const SizedBox(height: 8),
        const Notice(GoalsAsideText.notABankLock, icon: Icons.info_outline),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    return Form(
      key: _form,
      child: SheetBody(
        title: goal == null ? 'Add a goal' : 'Edit ${goal.name}',
        children: [
          LabeledField(
            label: 'What are you saving for?',
            child: TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              validator: (text) => (text ?? '').trim().isEmpty
                  ? 'Enter a name, such as School fees.'
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          AmountField(controller: _target, label: 'Target'),
          const SizedBox(height: 16),
          // What a savings app's goal holds is what is saved.
          if (_pocketId == null) ...[
            AmountField(
              controller: _saved,
              label: 'Saved so far',
              allowZero: true,
            ),
            const SizedBox(height: 16),
          ],
          ?_savedIn(),
          DateField(
            label: 'Target date (optional)',
            value: _date,
            clearable: true,
            firstDate: widget.today,
            lastDate: CalendarDate(widget.today.year + 30, 12, 31),
            onChanged: (date) => setState(() => _date = date),
          ),
          if (_canKeepAside) ..._keepAside(context),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
          if (goal != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _delete,
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete goal'),
            ),
          ],
        ],
      ),
    );
  }
}

String _amountText(int? minor) => minor == null || minor == 0
    ? ''
    : formatMoney(Money(minor), withCurrency: false);
