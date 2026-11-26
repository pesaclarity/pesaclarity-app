import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../domain/savings/savings_account.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/selector_field.dart';
import '../../../theme/pesa_colors.dart';
import 'savings_text.dart';

/// Opens "Update balance" for [account]: what the savings app shows now,
/// one figure, or one for each goal when there are several. Money taken
/// out that is in no goal yet is given one first.
Future<void> showUpdateSavingsBalanceSheet(
  BuildContext context,
  SavingsAccountSummary account,
) => showAppSheet<void>(
  context: context,
  builder: (context) =>
      AmountsHiddenScope(child: UpdateSavingsBalanceSheet(account: account)),
);

class UpdateSavingsBalanceSheet extends ConsumerStatefulWidget {
  const UpdateSavingsBalanceSheet({required this.account, super.key});

  final SavingsAccountSummary account;

  @override
  ConsumerState<UpdateSavingsBalanceSheet> createState() =>
      _UpdateSavingsBalanceSheetState();
}

class _UpdateSavingsBalanceSheetState
    extends ConsumerState<UpdateSavingsBalanceSheet> {
  final _form = GlobalKey<FormState>();
  late final _balances = {
    for (final p in widget.account.pockets) p.id: TextEditingController(),
  };

  /// The goal chosen for each withdrawal in no goal yet, by transaction.
  final _chosen = <int, int>{};
  var _busy = false;
  var _missing = false;

  SavingsAccountSummary get _account => widget.account;

  @override
  void dispose() {
    for (final c in _balances.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// The balances typed, by goal: a goal left empty keeps its own.
  Map<int, int> get _typed => {
    for (final MapEntry(key: id, value: field) in _balances.entries)
      if (field.text.trim().isNotEmpty)
        id: AmountField.amountFrom(field.text, currency: _account.currency)!,
  };

  Future<void> _save() async {
    final loose = _account.unassigned;
    final allChosen = loose.every((e) => _chosen.containsKey(e.transactionId));
    setState(() => _missing = !allChosen);
    if (!_form.currentState!.validate() || !allChosen) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(savingsRepositoryProvider);
    for (final e in loose) {
      await repository.assignEntry(e.transactionId, _chosen[e.transactionId]);
    }
    final typed = _typed;
    if (typed.isNotEmpty) {
      await repository.updateBalances(
        _account.accountId,
        balanceByPocket: typed,
        at: ref.read(clockProvider)(),
      );
    }
    navigator.pop();
    if (typed.isEmpty) return;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text(SavingsText.balanceSaved)));
  }

  Future<void> _chooseGoal(SavingsEntry entry) async {
    final picked = await showOptionSheet<int>(
      context,
      title: SavingsText.whichGoalTitle,
      options: [for (final p in _account.pockets) (p.id, p.name)],
      selected: _chosen[entry.transactionId],
    );
    if (picked != null) setState(() => _chosen[entry.transactionId] = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final pockets = _account.pockets;
    final loose = _account.unassigned;
    final name = _account.product?.name ?? _account.name;
    return Form(
      key: _form,
      child: SheetBody(
        title: SavingsText.updateBalance,
        subtitle: SavingsText.updateIntro(name),
        children: [
          if (loose.isNotEmpty) ...[
            const SectionLabel(SavingsText.whichGoalTitle),
            for (final e in loose) ...[
              SelectorField(
                key: Key('savings-assign-${e.transactionId}'),
                label: SavingsText.withdrawal(
                  shownMoney(
                    context,
                    e.amountMinor,
                    currency: _account.currency,
                  ),
                  SavingsText.day(CalendarDate.local(e.at), today.year),
                ),
                value:
                    _account.pocket(_chosen[e.transactionId])?.name ??
                    SavingsText.chooseGoal,
                onTap: () => _chooseGoal(e),
              ),
              const SizedBox(height: 12),
            ],
            if (_missing)
              Text(
                SavingsText.chooseEach,
                style: theme.textTheme.bodySmall!.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            const SizedBox(height: 8),
          ],
          for (final p in pockets) ...[
            AmountField(
              key: Key('savings-balance-${p.id}'),
              controller: _balances[p.id]!,
              label: pockets.length == 1
                  ? SavingsText.balance
                  : [p.name, if (p.hasCode) p.code].join(' · '),
              currency: _account.currency,
              allowZero: true,
            ),
            const SizedBox(height: 16),
          ],
          Text(
            SavingsText.interestRule,
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('savings-update-save'),
            onPressed: _busy || pockets.isEmpty ? null : _save,
            child: const Text(SavingsText.save),
          ),
        ],
      ),
    );
  }
}
