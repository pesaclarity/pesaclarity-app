import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../domain/spaces/line_routing.dart';
import '../../../shared/names.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/pesa_colors.dart';
import '../application/routing_providers.dart';
import '../application/spaces_providers.dart';
import 'till_sheet.dart';

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
    final space = ref.watch(activeSpaceProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('home-shared-line'),
        child: ListTile(
          leading: Icon(Icons.circle, size: 10, color: colors.warning),
          minLeadingWidth: 10,
          title: Text(
            q.asksNumber
                ? _numberQuestion(q, space.name)
                : 'Was this for the business?',
          ),
          subtitle: Text(
            [
              if (q.asksNumber)
                '${shownMoney(context, q.amountMinor, currency: q.currency, withCurrency: true)} came in through it'
              else
                _what(context, q),
              if (more > 0) more == 1 ? '1 more to sort' : '$more more to sort',
            ].join(' · '),
          ),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: () => showAppSheet<void>(
            context: context,
            builder: (_) =>
                q.asksNumber ? _NumberSheet(q) : _SharedLineSheet(q),
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
      if (widget.question.onOwnAccount) {
        await ref
            .read(ownAccountAskerProvider)
            .answer(widget.question, forBusiness: forBusiness, always: _always);
      } else {
        await ref
            .read(sharedLineRouterProvider)
            .answer(
              widget.question,
              businessId: ref.read(activeSpaceProvider).id,
              forBusiness: forBusiness,
              always: _always,
            );
      }
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
            // On the business's own account, the owner's own spending is
            // "This was for me" (decision 0027, section 6).
            child: Text(q.onOwnAccount ? 'This was for me' : 'Personal'),
          ),
        ),
      ],
    );
  }
}

/// "Is till 123456 Vegetable stall's?"
String _numberQuestion(SharedLineQuestion q, String business) =>
    "Is ${channelLabel(q.through.kind, q.through.number ?? '').toLowerCase()} "
    "$business's?";

/// Asked once for a till or paybill the app has not seen (decision 0027,
/// section 4; approved screens, choice 4): "Yes" names it and sends this
/// payment, and later ones through it, to the business; "No" leaves the
/// payment to today's "Was this for the business?".
class _NumberSheet extends ConsumerStatefulWidget {
  const _NumberSheet(this.question);

  final SharedLineQuestion question;

  @override
  ConsumerState<_NumberSheet> createState() => _NumberSheetState();
}

class _NumberSheetState extends ConsumerState<_NumberSheet> {
  var _busy = false;

  Future<void> _answer({required bool ours}) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(sharedLineRouterProvider)
          .answerNumber(
            widget.question,
            businessId: ref.read(activeSpaceProvider).id,
            ours: ours,
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
    final business = ref.watch(activeSpaceProvider).name;
    final amount = shownMoney(
      context,
      q.amountMinor,
      currency: q.currency,
      withCurrency: true,
    );
    final kind = q.through.kind == ChannelKind.paybill ? 'paybill' : 'till';
    return SheetBody(
      title: _numberQuestion(q, business),
      subtitle: '$amount came in through it, on your M-Pesa.',
      children: [
        Text(
          'We ask once. Yes sends money in through this $kind to $business '
          'from now on.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        ButtonPair(
          primary: FilledButton(
            key: const Key('till-question-yes'),
            onPressed: _busy ? null : () => _answer(ours: true),
            child: const Text('Yes'),
          ),
          secondary: OutlinedButton(
            key: const Key('till-question-no'),
            onPressed: _busy ? null : () => _answer(ours: false),
            child: const Text('No'),
          ),
        ),
      ],
    );
  }
}
