import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/payees_repository.dart';
import '../../../domain/enums.dart';
import '../../../domain/ledger/ledger_entry.dart';
import '../../../domain/payees/payee_identifier.dart';
import '../../payees/presentation/category_picker.dart';

/// Opens the sheet that names the party behind [entry]. Does nothing when
/// the entry has no number or till to name.
Future<void> showNamePayeeSheet(BuildContext context, LedgerEntry entry) {
  final kind = entry.counterpartyKind;
  final value = entry.counterpartyValue;
  if (kind == null || value == null) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => NamePayeeSheet(
      identifier: PayeeIdentifier.stored(kind, value),
      suggestedName: entry.counterpartyName,
      isInflow: entry.isInflow,
    ),
  );
}

/// Names a number once; its name and category then apply to every past and
/// future transaction from it.
class NamePayeeSheet extends ConsumerStatefulWidget {
  const NamePayeeSheet({
    required this.identifier,
    required this.isInflow,
    this.suggestedName,
    super.key,
  });

  final PayeeIdentifier identifier;
  final bool isInflow;
  final String? suggestedName;

  @override
  ConsumerState<NamePayeeSheet> createState() => _NamePayeeSheetState();
}

class _NamePayeeSheetState extends ConsumerState<NamePayeeSheet> {
  late final _name = TextEditingController(text: widget.suggestedName ?? '');
  int? _categoryId;
  String? _error;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name, such as John');
      return;
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    await ref
        .read(payeesRepositoryProvider)
        .name(
          widget.identifier,
          displayName: name,
          defaultCategoryId: _categoryId,
        );
    if (mounted) Navigator.pop(context);
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Name this payee', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${widget.identifier.value}. The name applies to every '
              'transaction with this number, past and future.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
            ),
            const SizedBox(height: 12),
            CategorySelectorField(
              key: const Key('name-payee-category'),
              label: widget.isInflow
                  ? 'What was it? Gift, loan or repayment'
                  : 'Category',
              selectedId: _categoryId,
              allowType: (type) => widget.isInflow
                  ? type != CategoryType.expense
                  : type != CategoryType.income,
              onChanged: (id) => setState(() => _categoryId = id),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
