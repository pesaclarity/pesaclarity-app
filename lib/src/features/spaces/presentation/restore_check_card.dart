import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/repositories/restore_check.dart';
import '../../../domain/spaces/money_between_spaces.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/figures.dart';
import '../../../theme/pesa_colors.dart';
import '../application/restore_check_providers.dart';

/// "3 payments on one side only", on the restored space's Today or Home
/// (decision 0027, section 7), with the amber dot of the other "needs you"
/// cards. Nothing when every payment has both sides.
class RestoreCheckCard extends ConsumerWidget {
  const RestoreCheckCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sided = ref.watch(oneSidedProvider).value;
    if (sided == null) return const SizedBox.shrink();
    final colors = PesaColors.of(context);
    final keeps = sided.personalRestored
        ? sided.business.name
        : 'Your ${sided.lineName}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('restore-check-card'),
        child: ListTile(
          leading: Icon(Icons.circle, size: 10, color: colors.warning),
          minLeadingWidth: 10,
          title: Text(oneSidedTitle(sided.payments.length)),
          subtitle: Text('After the restore · $keeps still has them'),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: () => showAppSheet<void>(
            context: context,
            builder: (_) => AmountsHiddenScope(child: RestoreCheckSheet(sided)),
          ),
        ),
      ),
    );
  }
}

/// "3 payments on one side only".
String oneSidedTitle(int n) =>
    n == 1 ? '1 payment on one side only' : '$n payments on one side only';

String _day(DateTime at) {
  final d = CalendarDate.local(at);
  return '${weekdayName(d).substring(0, 3)} ${shortDate(d)}';
}

/// What is on one side only, and the owner's three answers: make them
/// again, leave them apart, or (when the business is short) they were the
/// owner's own.
class RestoreCheckSheet extends ConsumerStatefulWidget {
  const RestoreCheckSheet(this.sided, {super.key});

  final OneSided sided;

  @override
  ConsumerState<RestoreCheckSheet> createState() => _RestoreCheckSheetState();
}

class _RestoreCheckSheetState extends ConsumerState<RestoreCheckSheet> {
  var _answer = OneSidedAnswer.makeAgain;
  var _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await ref.read(oneSidedControllerProvider).answer(widget.sided, _answer);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sided = widget.sided;
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final business = sided.business.name;
    final short = shortSpaceName(business);
    final line = sided.lineName;
    final restored = sided.personalRestored ? 'Personal' : business;
    final from = sided.backupAt == null
        ? 'from a backup'
        : 'from a backup of ${_day(sided.backupAt!)}';
    final allSales = sided.payments.every((p) => p.categoryKey == 'sales');
    final subtitle = sided.personalRestored
        ? '$restored was restored $from. $business has these '
              '${allSales ? 'sales' : 'payments'} on your $line. Personal '
              'does not count them.'
        : '$restored was restored $from. Your $line in Personal still holds '
              "these as the $short's.";
    final answers = <(OneSidedAnswer, String)>[
      (
        OneSidedAnswer.makeAgain,
        'Make them again in ${sided.personalRestored ? 'Personal' : business}',
      ),
      (OneSidedAnswer.leaveApart, 'Leave them apart'),
      if (!sided.personalRestored) (OneSidedAnswer.wereMine, 'They were mine'),
    ];
    final held = shownMoney(context, sided.heldMinor.abs(), withCurrency: true);
    final note = switch (_answer) {
      OneSidedAnswer.makeAgain when sided.personalRestored =>
        "They count in your $line's balance as the $short's. No row is "
            'added to Personal.',
      OneSidedAnswer.makeAgain =>
        'They come back on your $line with amount, time and code. Names and '
            'categories were only in the $short, so add them again if you '
            'need them.',
      OneSidedAnswer.leaveApart when sided.personalRestored =>
        'Nothing changes. $business keeps these, and Personal does not '
            'count them.',
      OneSidedAnswer.leaveApart =>
        sided.heldMinor >= 0
            ? "Nothing changes. Personal keeps $held as the $short's, and "
                  'the $short does not show these.'
            : 'Nothing changes. Personal keeps what the $short owes you, '
                  'and the $short does not show these.',
      OneSidedAnswer.wereMine =>
        'They become your own payments in Personal, and the '
            "$short's part of your $line is undone.",
    };
    final button = switch (_answer) {
      OneSidedAnswer.makeAgain => 'Make them again',
      OneSidedAnswer.leaveApart => 'Leave them apart',
      OneSidedAnswer.wereMine => 'They were mine',
    };
    return SheetBody(
      title: oneSidedTitle(sided.payments.length),
      subtitle: subtitle,
      children: [
        GroupedSection(
          key: const Key('restore-check-payments'),
          children: [
            for (final p in sided.payments)
              LabelValueRow(
                label: _label(p, personalRestored: sided.personalRestored),
                detail: sided.personalRestored
                    ? '${_day(p.at)}, ${formatTime(p.at)}'
                    : [
                        '${_day(p.at)}, ${formatTime(p.at)}',
                        ?p.code,
                      ].join(' · '),
                value:
                    (p.inflow ? '' : '-') +
                    shownMoney(context, p.amountMinor, currency: p.currency),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'What to do',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: colors.textMuted,
            ),
          ),
        ),
        ChoiceMenu<OneSidedAnswer>(
          key: const Key('restore-check-answer'),
          name: 'What to do',
          expand: true,
          value: _answer,
          options: answers,
          itemKey: (a) => Key('restore-check-${a.name}'),
          onChanged: (a) => setState(() => _answer = a),
        ),
        const SizedBox(height: 8),
        Text(
          note,
          key: const Key('restore-check-note'),
          style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('restore-check-go'),
          onPressed: _busy ? null : _go,
          child: Text(button),
        ),
      ],
    );
  }
}

/// A payment's name in the list: "Money in", "Money out"; with what the
/// business knows of it, "Sales · GRACE WAMBUI".
String _label(OneSidedPayment p, {required bool personalRestored}) {
  if (personalRestored && (p.categoryName != null || p.name != null)) {
    return [?p.categoryName, ?p.name].join(' · ');
  }
  return switch (p.kind) {
    OneSidedKind.pay => 'Paid yourself',
    OneSidedKind.putIn => 'Put money in',
    _ => p.inflow ? 'Money in' : 'Money out',
  };
}
