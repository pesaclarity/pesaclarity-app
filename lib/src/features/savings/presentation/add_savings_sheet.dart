import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/savings_repository.dart';
import '../../../domain/savings/savings_product.dart';
import '../../../domain/savings/savings_prompt.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/sections.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/savings_providers.dart';
import 'savings_pocket_sheet.dart';
import 'savings_text.dart';

/// Opens "Add Chumz" for [product]: its name, each account code found in
/// the payments as a goal to name and lock, and the balance, optional.
/// [promptedTransactionId] is the payment the question was asked under.
Future<void> showAddSavingsSheet(
  BuildContext context,
  SavingsProduct product, {
  int? promptedTransactionId,
}) => showAppSheet<void>(
  context: context,
  builder: (context) => AddSavingsSheet(
    product: product,
    promptedTransactionId: promptedTransactionId,
  ),
);

class AddSavingsSheet extends ConsumerStatefulWidget {
  const AddSavingsSheet({
    required this.product,
    this.promptedTransactionId,
    super.key,
  });

  final SavingsProduct product;
  final int? promptedTransactionId;

  @override
  ConsumerState<AddSavingsSheet> createState() => _AddSavingsSheetState();
}

/// What the person types for one account code.
class _Draft {
  _Draft(this.code);

  final String code;
  final name = TextEditingController();
  final balance = TextEditingController();
  CalendarDate? lockedUntil;

  void dispose() {
    name.dispose();
    balance.dispose();
  }
}

class _AddSavingsSheetState extends ConsumerState<AddSavingsSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product.name);
  final _balance = TextEditingController();
  final _drafts = <String, _Draft>{};
  var _busy = false;

  SavingsProduct get _product => widget.product;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    for (final d in _drafts.values) {
      d.dispose();
    }
    super.dispose();
  }

  _Draft _draft(String code) => _drafts.putIfAbsent(code, () => _Draft(code));

  Future<void> _add(List<SavingsCodeFound> codes) async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final repository = ref.read(savingsRepositoryProvider);
    final now = ref.read(clockProvider)();
    final currency = _product.currency;
    final drafts = [for (final c in codes) _draft(c.code)];
    final added = await repository.add(
      _product,
      at: now,
      name: _name.text.trim(),
      pockets: [
        for (final d in drafts)
          SavingsPocketDraft(
            code: d.code,
            name: d.name.text.trim().isEmpty
                ? (d.code.isEmpty ? SavingsText.noCode : d.code)
                : d.name.text.trim(),
            lockedUntil: d.lockedUntil?.startInstant,
          ),
      ],
      promptedTransactionId: widget.promptedTransactionId,
    );
    // The balance as one figure for one goal, or one for each.
    final typed = <String, int>{
      if (drafts.length == 1)
        drafts.single.code: ?_typed(_balance.text, currency)
      else
        for (final d in drafts) d.code: ?_typed(d.balance.text, currency),
    };
    final account = typed.isEmpty
        ? null
        : await repository.account(added.accountId);
    final byCode = {
      for (final p in [...?account?.pockets]) p.code: p.id,
    };
    final balances = {
      for (final MapEntry(key: code, value: minor) in typed.entries)
        ?byCode[code]: minor,
    };
    if (balances.isNotEmpty) {
      try {
        await repository.updateBalances(
          added.accountId,
          balanceByPocket: balances,
          at: now,
        );
      } on StateError {
        // Money taken out needs a goal first; the page asks for it.
        messenger?.showSnackBar(
          const SnackBar(content: Text(SavingsText.balanceLater)),
        );
      }
    }
    navigator.pop();
  }

  /// The amount typed, or null when the field is empty.
  static int? _typed(String text, String currency) => text.trim().isEmpty
      ? null
      : AmountField.amountFrom(text, currency: currency);

  @override
  Widget build(BuildContext context) {
    final discovery = ref.watch(savingsDiscoveryProvider(_product.id)).value;
    final today = CalendarDate.local(ref.watch(clockProvider)());
    final codes = discovery?.codes ?? const <SavingsCodeFound>[];
    final several = codes.length > 1;
    return Form(
      key: _form,
      child: SheetBody(
        title: SavingsText.add(_product),
        children: [
          _NameAndProvider(name: _name, product: _product),
          const SizedBox(height: 14),
          _PaidThrough(_product),
          if (codes.isNotEmpty) ...[
            SectionLabel(
              SavingsText.goalsFound,
              trailing: Text(
                SavingsText.fromCodes,
                style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(color: PesaColors.of(context).textMuted),
              ),
            ),
            for (final (i, code) in codes.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              _GoalCard(
                draft: _draft(code.code),
                today: today,
                product: _product,
                withBalance: several,
                onChanged: () => setState(() {}),
              ),
            ],
          ],
          const SizedBox(height: 18),
          if (!several)
            AmountField(
              key: const Key('add-savings-balance'),
              controller: _balance,
              label: SavingsText.currentBalance,
              currency: _product.currency,
              allowZero: true,
            ),
          const SizedBox(height: 6),
          Text(
            SavingsText.typeWhatItShows(_product, _name.text),
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: PesaColors.of(context).textMuted),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('add-savings'),
            onPressed: _busy || discovery == null ? null : () => _add(codes),
            child: const Text(SavingsText.addButton),
          ),
        ],
      ),
    );
  }
}

/// Name and provider side by side while both fit; with large text, one
/// under the other. The provider is fixed by the product.
class _NameAndProvider extends StatelessWidget {
  const _NameAndProvider({required this.name, required this.product});

  final TextEditingController name;
  final SavingsProduct product;

  @override
  Widget build(BuildContext context) {
    final nameField = LabeledField(
      label: SavingsText.name,
      child: TextFormField(
        key: const Key('add-savings-name'),
        controller: name,
        textCapitalization: TextCapitalization.words,
        validator: (text) => (text ?? '').trim().isEmpty
            ? SavingsText.nameMissing(product)
            : null,
      ),
    );
    final providerField = LabeledField(
      label: SavingsText.provider,
      child: TextFormField(
        key: const Key('add-savings-provider'),
        initialValue: product.provider,
        readOnly: true,
        canRequestFocus: false,
      ),
    );
    final style = Theme.of(context).textTheme.bodyLarge!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final half = (constraints.maxWidth - Layout.cardGap) / 2;
        // The text and the field's padding on each side.
        final fits =
            textLineWidth(context, product.provider, style) + 40 <= half &&
            textLineWidth(context, SavingsText.provider, style) <= half;
        if (!fits) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [nameField, const SizedBox(height: 12), providerField],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: nameField),
            const SizedBox(width: Layout.cardGap),
            Expanded(child: providerField),
          ],
        );
      },
    );
  }
}

/// "Paid through M-Pesa paybill NABO CAPITAL LTD", in a field's box.
class _PaidThrough extends StatelessWidget {
  const _PaidThrough(this.product);

  final SavingsProduct product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.phone_android,
              size: 20,
              color: theme.colorScheme.onSurface,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    SavingsText.paidThrough,
                    style: theme.textTheme.bodySmall!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                  Text(product.paidThrough, style: theme.textTheme.titleSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One account code to name, lock and, with several, give a balance.
class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.draft,
    required this.today,
    required this.product,
    required this.withBalance,
    required this.onChanged,
  });

  final _Draft draft;
  final CalendarDate today;
  final SavingsProduct product;
  final bool withBalance;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    final code = draft.code.isEmpty ? SavingsText.noCode : draft.code;
    final label = '$code — ${SavingsText.nameThisGoal}';
    return Container(
      key: Key('add-savings-goal-${draft.code}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Layout.panelRadius),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: code,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const TextSpan(text: ' — ${SavingsText.nameThisGoal}'),
                ],
              ),
              style: muted,
            ),
          ),
          const SizedBox(height: 6),
          Semantics(
            label: label,
            child: TextFormField(
              key: Key('add-savings-goal-name-${draft.code}'),
              controller: draft.name,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              decoration: const InputDecoration(
                hintText: SavingsText.goalHint,
                counterText: '',
              ),
            ),
          ),
          const SizedBox(height: 6),
          LockUntilRow(
            value: draft.lockedUntil,
            today: today,
            onChanged: (day) {
              draft.lockedUntil = day;
              onChanged();
            },
          ),
          if (withBalance) ...[
            const SizedBox(height: 8),
            AmountField(
              key: Key('add-savings-goal-balance-${draft.code}'),
              controller: draft.balance,
              label: SavingsText.goalBalance,
              currency: product.currency,
              allowZero: true,
            ),
          ],
        ],
      ),
    );
  }
}
