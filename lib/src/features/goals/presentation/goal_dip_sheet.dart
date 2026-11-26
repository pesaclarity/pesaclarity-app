import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/repositories/goals_repository.dart';
import '../../../domain/goals/goals_aside.dart';
import '../../../domain/goals/savings_goal.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../theme/pesa_colors.dart';
import '../application/goals_aside_providers.dart';
import '../application/goals_overview_provider.dart';
import 'goals_aside_text.dart';

/// What to do after a dip. Nothing moves in the bank either way.
enum DipAnswer {
  /// The goal keeps all it holds aside, so the next money in fills it
  /// first. The default.
  topUp,

  /// The goal's saved amount comes down by the dip.
  lower,

  /// The goal still shows what is saved, but the dip is no longer aside.
  leave,
}

/// Opens what to do about [dip].
Future<void> showGoalDipSheet(
  BuildContext context, {
  required GoalDip dip,
  required CalendarDate today,
}) => showAppSheet<void>(
  context: context,
  builder: (context) => AmountsHiddenScope(
    child: GoalDipSheet(dip: dip, today: today),
  ),
);

/// "You dipped KES 1,500 into School fees": top it up from the next money
/// in (chosen first), lower what is saved, or leave it.
class GoalDipSheet extends ConsumerStatefulWidget {
  const GoalDipSheet({required this.dip, required this.today, super.key});

  final GoalDip dip;
  final CalendarDate today;

  @override
  ConsumerState<GoalDipSheet> createState() => _GoalDipSheetState();
}

class _GoalDipSheetState extends ConsumerState<GoalDipSheet> {
  var _answer = DipAnswer.topUp;
  var _busy = false;

  SavingsGoal get _goal => widget.dip.goal;

  int get _lowered {
    final saved = _goal.savedMinor - widget.dip.dipMinor;
    return saved < 0 ? 0 : saved;
  }

  Future<void> _done() async {
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final kept = container.read(keptAsideProvider.notifier);
    final goal = _goal;
    final dip = widget.dip.dipMinor;
    switch (_answer) {
      case DipAnswer.topUp:
        await kept.topUp(goal.id, dip);
      case DipAnswer.lower:
        await container
            .read(goalsRepositoryProvider)
            .update(_withSaved(goal, _lowered));
        await kept.savedChanged(goal.id);
      case DipAnswer.leave:
        await kept.leave(goal.id, dip);
    }
    refreshGoals(container);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final goal = _goal;
    final dip = widget.dip;
    String money(int minor) =>
        shownMoney(context, minor, currency: goal.currency);
    final note = switch (_answer) {
      DipAnswer.topUp => GoalsAsideText.topUpNote(money(dip.dipMinor)),
      DipAnswer.lower => GoalsAsideText.lowerNote(
        goal.name,
        money(_lowered),
        money(goal.targetMinor),
        pace: switch (_withSaved(
          goal,
          _lowered,
        ).monthlyNeededMinor(widget.today)) {
          final needed? when goal.targetDate != null => money(needed),
          _ => null,
        },
      ),
      DipAnswer.leave => GoalsAsideText.leaveNote(
        goal.name,
        money(goal.savedMinor),
        money(dip.stillAsideMinor),
      ),
    };
    return SheetBody(
      title: GoalsAsideText.dipped(
        shownMoney(
          context,
          dip.dipMinor,
          currency: goal.currency,
          withCurrency: true,
        ),
        goal.name,
      ),
      subtitle: GoalsAsideText.dipSubtitle(
        money(goal.savedMinor),
        money(dip.stillAsideMinor),
      ),
      children: [
        LabeledField(
          label: GoalsAsideText.whatToDo,
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ChoiceMenu<DipAnswer>(
              key: const Key('goal-dip-answer'),
              name: GoalsAsideText.whatToDo,
              expand: true,
              options: [
                (DipAnswer.topUp, GoalsAsideText.topUp),
                (DipAnswer.lower, GoalsAsideText.lower(money(_lowered))),
                (DipAnswer.leave, GoalsAsideText.leave),
              ],
              value: _answer,
              itemKey: (answer) => Key('goal-dip-${answer.name}'),
              onChanged: (answer) => setState(() => _answer = answer),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          note,
          key: const Key('goal-dip-note'),
          style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('goal-dip-done'),
          onPressed: _busy ? null : _done,
          child: const Text('Done'),
        ),
      ],
    );
  }
}

SavingsGoal _withSaved(SavingsGoal goal, int savedMinor) => SavingsGoal(
  id: goal.id,
  name: goal.name,
  targetMinor: goal.targetMinor,
  savedMinor: savedMinor,
  targetDate: goal.targetDate,
  currency: goal.currency,
  status: goal.status,
  backing: goal.backing,
);
