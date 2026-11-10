import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/names.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/pesa_colors.dart';
import '../application/routing_providers.dart';
import '../application/spaces_providers.dart';

/// "Was this for the business?" for payments on an account used for both,
/// on a business's Home. Shows the newest one; tapping it opens the
/// answers. Nothing when there are none.
class SharedLineCard extends ConsumerWidget {
  const SharedLineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final questions = ref.watch(sharedLineQuestionsProvider).value ?? const [];
    if (questions.isEmpty) return const SizedBox.shrink();
    final q = questions.first;
    final colors = PesaColors.of(context);
    final more = questions.length - 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('home-shared-line'),
        child: ListTile(
          leading: Icon(Icons.circle, size: 10, color: colors.warning),
          minLeadingWidth: 10,
          title: const Text('Was this for the business?'),
          subtitle: Text(
            [
              _what(context, q),
              if (more > 0) more == 1 ? '1 more to sort' : '$more more to sort',
            ].join(' · '),
          ),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: () => showAppSheet<void>(
            context: context,
            builder: (_) => _SharedLineSheet(q),
          ),
        ),
      ),
    );
  }
}

/// The person named in [q], in title case, or null.
String? _nameOf(SharedLineQuestion q) =>
    q.name == null || q.name!.trim().isEmpty ? null : titleCase(q.name);

/// `Grace Wambui sent you 650`, `You paid Mzee Juma 650`.
String _what(BuildContext context, SharedLineQuestion q) {
  final name = _nameOf(q);
  final amount = shownMoney(context, q.amountMinor, currency: q.currency);
  return q.isInflow
      ? '${name ?? 'Someone'} sent you $amount'
      : 'You paid ${name ?? 'someone'} $amount';
}

/// The answers: business or personal, and whether to do the same for this
/// person from now on.
class _SharedLineSheet extends ConsumerStatefulWidget {
  const _SharedLineSheet(this.question);

  final SharedLineQuestion question;

  @override
  ConsumerState<_SharedLineSheet> createState() => _SharedLineSheetState();
}

class _SharedLineSheetState extends ConsumerState<_SharedLineSheet> {
  var _always = true;
  var _busy = false;

  Future<void> _answer({required bool forBusiness}) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(sharedLineRouterProvider)
          .answer(
            widget.question,
            businessId: ref.read(activeSpaceProvider).id,
            forBusiness: forBusiness,
            always: _always,
          );
      ref.invalidate(sharedLineQuestionsProvider);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final name = _nameOf(q);
    return SheetBody(
      title: 'Was this for the business?',
      subtitle: '${_what(context, q)}.',
      children: [
        if (q.personKey != null && name != null) ...[
          SwitchListTile.adaptive(
            key: const Key('shared-line-always'),
            contentPadding: EdgeInsets.zero,
            value: _always,
            onChanged: (v) => setState(() => _always = v),
            title: Text('Always do this for $name'),
          ),
          const SizedBox(height: 8),
        ],
        ButtonPair(
          primary: FilledButton(
            key: const Key('shared-line-business'),
            onPressed: _busy ? null : () => _answer(forBusiness: true),
            child: Text(q.isInflow ? 'Business sale' : 'Business cost'),
          ),
          secondary: OutlinedButton(
            key: const Key('shared-line-personal'),
            onPressed: _busy ? null : () => _answer(forBusiness: false),
            child: const Text('Personal'),
          ),
        ),
      ],
    );
  }
}
