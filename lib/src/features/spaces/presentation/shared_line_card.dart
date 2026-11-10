import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../shared/names.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/layout.dart';
import '../application/routing_providers.dart';
import '../application/spaces_providers.dart';

/// "Was this for the business?" for payments on an account used for both,
/// on a business's Home. Shows the newest one; nothing when there are none.
class SharedLineCard extends ConsumerStatefulWidget {
  const SharedLineCard({super.key});

  @override
  ConsumerState<SharedLineCard> createState() => _SharedLineCardState();
}

class _SharedLineCardState extends ConsumerState<SharedLineCard> {
  var _always = true;
  var _busy = false;

  Future<void> _answer(
    SharedLineQuestion q, {
    required bool forBusiness,
  }) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(sharedLineRouterProvider)
          .answer(
            q,
            businessId: ref.read(activeSpaceProvider).id,
            forBusiness: forBusiness,
            always: _always,
          );
      ref.invalidate(sharedLineQuestionsProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = ref.watch(sharedLineQuestionsProvider).value ?? const [];
    if (questions.isEmpty) return const SizedBox.shrink();
    final q = questions.first;
    final theme = Theme.of(context);
    final name = q.name == null || q.name!.trim().isEmpty
        ? null
        : titleCase(q.name);
    final amount = shownAmounts(
      context,
      formatMoney(Money(q.amountMinor, currency: q.currency)),
    );
    final who = name ?? 'Someone';
    final text = q.isInflow
        ? '$who sent you $amount. Was this for the business?'
        : 'You paid ${name ?? 'someone'} $amount. Was this for the business?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('home-shared-line'),
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(text, style: theme.textTheme.bodyLarge),
              const SizedBox(height: 12),
              ButtonPair(
                primary: FilledButton(
                  key: const Key('shared-line-business'),
                  onPressed: _busy ? null : () => _answer(q, forBusiness: true),
                  child: Text(q.isInflow ? 'Business sale' : 'Business cost'),
                ),
                secondary: OutlinedButton(
                  key: const Key('shared-line-personal'),
                  onPressed: _busy
                      ? null
                      : () => _answer(q, forBusiness: false),
                  child: const Text('Personal'),
                ),
              ),
              if (q.personKey != null && name != null)
                CheckboxListTile(
                  key: const Key('shared-line-always'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _always,
                  onChanged: (v) => setState(() => _always = v ?? false),
                  title: Text('Always do this for $name'),
                ),
              if (questions.length > 1)
                Text(
                  questions.length == 2
                      ? '1 more to sort'
                      : '${questions.length - 1} more to sort',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
