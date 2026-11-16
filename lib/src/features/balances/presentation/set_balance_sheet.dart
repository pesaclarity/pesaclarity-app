import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/balances_repository.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/balances_providers.dart';
import 'balance_text.dart';

/// Asks what [balance]'s account really holds now and records the
/// difference as a balance correction.
Future<void> showSetBalanceSheet(
  BuildContext context,
  AccountBalance balance,
) => showAppSheet<void>(
  context: context,
  builder: (context) => AmountsHiddenScope(child: SetBalanceSheet(balance)),
);

class SetBalanceSheet extends ConsumerStatefulWidget {
  const SetBalanceSheet(this.balance, {super.key});

  final AccountBalance balance;

  @override
  ConsumerState<SetBalanceSheet> createState() => _SetBalanceSheetState();
}

class _SetBalanceSheetState extends ConsumerState<SetBalanceSheet> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  late var _owes = widget.balance.heldMinor < 0;
  var _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  AccountBalance get _balance => widget.balance;

  String get _currency => _balance.opening.currency;

  bool get _canOweFuliza => _balance.opening.canOweFuliza;

  /// What the person says it holds, below zero when they owe Fuliza.
  int? get _stated {
    final typed = AmountField.amountFrom(_amount.text, currency: _currency);
    if (typed == null) return null;
    return _owes && _canOweFuliza ? -typed : typed;
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final stated = _stated!;
    final difference = stated - _balance.heldMinor;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (difference == 0) {
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text(BalanceText.alreadyMatches)),
      );
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(balancesRepositoryProvider)
        .setBalance(
          _balance.account.id,
          statedMinor: stated,
          differenceMinor: difference,
          at: ref.read(clockProvider)(),
          currency: _currency,
        );
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text(BalanceText.correctionSaved)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final stated = _stated;
    final difference = stated == null ? null : stated - _balance.heldMinor;
    String money(int minor) => shownMoney(context, minor, currency: _currency);
    final name = _balance.account.name;

    return Form(
      key: _form,
      child: SheetBody(
        title: BalanceText.setBalance,
        subtitle: BalanceText.setBalanceIntro,
        children: [
          Card(
            child: Column(
              children: [
                LabelValueRow(label: 'Account', value: name),
                LabelValueRow(
                  key: const Key('set-balance-app-shows'),
                  label: BalanceText.appShows,
                  value: money(_balance.heldMinor),
                ),
                if (difference != null && difference != 0)
                  LabelValueRow(
                    key: const Key('set-balance-correction'),
                    label: BalanceText.correction,
                    value: '${difference > 0 ? '+' : ''}${money(difference)}',
                    valueColor: difference > 0
                        ? colors.successText
                        : theme.colorScheme.onSurface,
                    strong: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: Layout.cardGap),
          if (_canOweFuliza) ...[
            AdaptiveSegmented<bool>(
              key: const Key('set-balance-owes'),
              showSelectedIcon: false,
              segments: const [
                (false, BalanceText.hasMoney),
                (true, BalanceText.owesFuliza),
              ],
              selected: _owes,
              onChanged: (owes) => setState(() => _owes = owes),
            ),
            const SizedBox(height: 8),
            Text(BalanceText.fulizaHelp, style: theme.textTheme.bodySmall),
            const SizedBox(height: Layout.cardGap),
          ],
          AmountField(
            key: const Key('set-balance-amount'),
            controller: _amount,
            label: BalanceText.accountSays(name),
            currency: _currency,
            allowZero: true,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Layout.cardGap),
          Text(
            BalanceText.correctionNote,
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('set-balance-save'),
            onPressed: _saving ? null : _save,
            child: const Text(BalanceText.saveCorrection),
          ),
        ],
      ),
    );
  }
}
