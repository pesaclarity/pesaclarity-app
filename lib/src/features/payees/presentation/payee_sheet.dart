import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database.dart';
import '../../../data/repositories/payees_repository.dart';
import '../../../data/repositories/purpose_repository.dart';
import '../../../domain/export/export_tables.dart';
import '../../../domain/payees/payee_identifier.dart';
import '../../../shared/names.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../theme/pesa_colors.dart';
import 'category_picker.dart';

/// Names the party behind [identifier], or edits [payee] when given. The
/// name, category and leak type apply to every past and future transaction
/// from that number, till or paybill.
///
/// [moneyIn], when known, is the way the money moved: money in asks what it
/// was and offers no spending categories; money out offers no income ones.
///
/// Returns the payee id once saved, or null when dismissed.
Future<int?> showPayeeSheet(
  BuildContext context, {
  PayeeIdentifier? identifier,
  Payee? payee,
  String? suggestedName,
  bool? moneyIn,
}) {
  assert(identifier != null || payee != null, 'needs something to name');
  return showAppSheet<int>(
    context: context,
    builder: (context) => PayeeSheet(
      identifier: identifier,
      payee: payee,
      suggestedName: suggestedName,
      moneyIn: moneyIn,
    ),
  );
}

class PayeeSheet extends ConsumerStatefulWidget {
  const PayeeSheet({
    this.identifier,
    this.payee,
    this.suggestedName,
    this.moneyIn,
    super.key,
  });

  final PayeeIdentifier? identifier;
  final Payee? payee;
  final String? suggestedName;

  /// The way the money moved, when the sheet opens from one transaction.
  final bool? moneyIn;

  @override
  ConsumerState<PayeeSheet> createState() => _PayeeSheetState();
}

class _PayeeSheetState extends ConsumerState<PayeeSheet> {
  late final _name = TextEditingController(
    text: widget.payee?.displayName ?? titleCase(widget.suggestedName),
  );
  late int? _categoryId = widget.payee?.defaultCategoryId;
  late LeakType _leakType = widget.payee?.leakType ?? LeakType.none;
  late bool _askPurpose = widget.payee?.askPurpose ?? false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final repo = ref.read(payeesRepositoryProvider);
    final navigator = Navigator.of(context);
    final existing = widget.payee;
    final int id;
    if (existing != null) {
      await repo.update(
        existing.id,
        displayName: _name.text,
        defaultCategoryId: Value(_categoryId),
        leakType: _leakType,
      );
      if (_askPurpose != existing.askPurpose) {
        await ref
            .read(purposeRepositoryProvider)
            .setAskPurpose(existing.id, ask: _askPurpose);
      }
      id = existing.id;
    } else {
      id = await repo.name(
        widget.identifier!,
        displayName: _name.text,
        defaultCategoryId: _categoryId,
        leakType: _leakType,
      );
    }
    if (mounted) navigator.pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final name = _name.text.trim();
    final canSave = !_saving && name.isNotEmpty && name.length <= 80;
    final who = widget.identifier?.label;
    final moneyIn = widget.moneyIn;

    return SheetBody(
      title: widget.payee == null ? 'Name this payee' : 'Edit payee',
      subtitle: who == null
          ? 'Changes apply to every past and future payment.'
          : 'Applies to every past and future payment to $who.',
      children: [
        TextField(
          controller: _name,
          autofocus: widget.payee == null,
          maxLength: 80,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'John (brother) or Naivas',
          ),
        ),
        const SizedBox(height: 12),
        CategorySelectorField(
          key: const Key('payee-category'),
          label: moneyIn ?? false
              ? 'What was it? Gift, loan or repayment'
              : 'Category',
          selectedId: _categoryId,
          allowType: moneyIn == null
              ? null
              : (type) => moneyIn
                    ? type != CategoryType.expense
                    : type != CategoryType.income,
          onChanged: (id) => setState(() => _categoryId = id),
        ),
        const SizedBox(height: 4),
        if (widget.payee != null)
          SwitchListTile.adaptive(
            key: const Key('payee-ask-purpose'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Ask what money from them is for'),
            subtitle: const Text(
              'For people whose money means different things',
            ),
            value: _askPurpose,
            onChanged: (v) => setState(() => _askPurpose = v),
          ),
        const SizedBox(height: 8),
        Text(
          'Leak type',
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 4),
        Text('Leaks add up on Insights.', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        ChoiceMenu<LeakType>(
          key: const Key('payee-leak-type'),
          name: 'Leak type',
          expand: true,
          options: [for (final t in LeakType.values) (t, leakTypeLabel(t))],
          value: _leakType,
          itemKey: (t) => Key('payee-leak-${t.name}'),
          onChanged: (t) => setState(() => _leakType = t),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
