import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/purpose_repository.dart';
import '../../../domain/income/money_purpose.dart';
import '../../../theme/pesa_colors.dart';

/// Asks what money in from [payeeName] was for.
Future<void> showWhatWasThis(
  BuildContext context, {
  required int transactionId,
  required String payeeName,
  required int amountMinor,
  required String currency,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => WhatWasThisSheet(
    transactionId: transactionId,
    payeeName: payeeName,
    amountMinor: amountMinor,
    currency: currency,
  ),
);

class WhatWasThisSheet extends ConsumerStatefulWidget {
  const WhatWasThisSheet({
    required this.transactionId,
    required this.payeeName,
    required this.amountMinor,
    required this.currency,
    super.key,
  });

  final int transactionId;
  final String payeeName;
  final int amountMinor;
  final String currency;

  @override
  ConsumerState<WhatWasThisSheet> createState() => _WhatWasThisSheetState();
}

class _WhatWasThisSheetState extends ConsumerState<WhatWasThisSheet> {
  MoneyPurpose? _purpose;
  var _alwaysUse = false;
  var _saving = false;

  Future<void> _save(MoneyPurpose purpose) async {
    setState(() => _saving = true);
    await ref
        .read(purposeRepositoryProvider)
        .answer(widget.transactionId, purpose, alwaysUse: _alwaysUse);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final amount = formatMoney(
      Money(widget.amountMinor, currency: widget.currency),
    );
    final purpose = _purpose;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('What was this?', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '$amount from ${widget.payeeName}. Their money has meant '
              'different things before.',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: RadioGroup<MoneyPurpose>(
                groupValue: purpose,
                onChanged: (value) => setState(() => _purpose = value),
                child: Column(
                  children: [
                    for (final (i, p) in MoneyPurpose.values.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      RadioListTile<MoneyPurpose>(
                        key: Key('purpose-${p.name}'),
                        value: p,
                        title: Text(p.label),
                        subtitle: p.hint == null ? null : Text(p.hint!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            CheckboxListTile(
              key: const Key('purpose-always'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _alwaysUse,
              onChanged: (v) => setState(() => _alwaysUse = v ?? false),
              title: Text('Always use this for ${widget.payeeName}'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('purpose-save'),
              onPressed: purpose == null || _saving
                  ? null
                  : () => _save(purpose),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
