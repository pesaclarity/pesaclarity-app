import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/purpose_repository.dart';
import '../../../domain/income/money_purpose.dart';
import '../../../shared/widgets/app_sheet.dart';

/// Asks what money in from [payeeName] was for.
Future<void> showWhatWasThis(
  BuildContext context, {
  required int transactionId,
  required String payeeName,
  required int amountMinor,
  required String currency,
}) => showAppSheet<void>(
  context: context,
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
    final amount = formatMoney(
      Money(widget.amountMinor, currency: widget.currency),
    );
    final purpose = _purpose;
    return SheetBody(
      title: 'What was this?',
      subtitle:
          '$amount from ${widget.payeeName}. Their money has meant '
          'different things before.',
      children: [
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
        SwitchListTile.adaptive(
          key: const Key('purpose-always'),
          contentPadding: EdgeInsets.zero,
          value: _alwaysUse,
          onChanged: (v) => setState(() => _alwaysUse = v),
          title: Text('Always use this for ${widget.payeeName}'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('purpose-save'),
          onPressed: purpose == null || _saving ? null : () => _save(purpose),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
