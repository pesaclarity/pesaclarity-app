import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/budget/until_next_money.dart';
import '../../../domain/income/make_it_last.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';
import '../../../theme/app_typography.dart';
import '../../../theme/pesa_colors.dart';
import '../application/income_providers.dart';

/// Offers a split for money that just arrived: bills first, a little kept
/// back, then a daily amount until the next money.
Future<void> showMakeItLast(
  BuildContext context, {
  required int arrivalId,
  required int arrivalMinor,
  required String from,
  required UntilNextMoney plan,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => MakeItLastSheet(
    arrivalId: arrivalId,
    arrivalMinor: arrivalMinor,
    from: from,
    plan: plan,
  ),
);

class MakeItLastSheet extends ConsumerStatefulWidget {
  const MakeItLastSheet({
    required this.arrivalId,
    required this.arrivalMinor,
    required this.from,
    required this.plan,
    super.key,
  });

  final int arrivalId;
  final int arrivalMinor;
  final String from;
  final UntilNextMoney plan;

  @override
  ConsumerState<MakeItLastSheet> createState() => _MakeItLastSheetState();
}

class _MakeItLastSheetState extends ConsumerState<MakeItLastSheet> {
  var _changing = false;
  var _saving = false;
  late final _daily = TextEditingController(
    text: formatMoney(Money(widget.plan.dailyMinor), withCurrency: false),
  );

  @override
  void dispose() {
    _daily.dispose();
    super.dispose();
  }

  int? get _chosenMinor {
    if (!_changing) return widget.plan.dailyMinor;
    return parseMoneyMinor(_daily.text);
  }

  Future<void> _use(int dailyMinor) async {
    setState(() => _saving = true);
    await ref
        .read(makeItLastProvider.notifier)
        .use(
          MakeItLastPin(
            arrivalId: widget.arrivalId,
            dailyMinor: dailyMinor,
            until: widget.plan.lastDay,
          ),
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final plan = widget.plan;
    String plain(int minor) => formatMoney(Money(minor), withCurrency: false);
    String day(CalendarDate d) =>
        '${weekdayName(d).substring(0, 3)} ${shortDate(d)}';

    final intro = switch (plan.basis) {
      NextMoneyBasis.rhythm when plan.nextMoney != null =>
        'Next money usually comes in about ${_days(plan.days)}. '
            'Make it last:',
      NextMoneyBasis.noDate => 'Make it last:',
      _ => 'Planning a week at a time. Make it last:',
    };
    final lasts = plan.lastsUntil;
    final note = plan.runsOutEarly && lasts != null
        ? 'At your usual pace it lasts until about ${day(lasts)}. '
              '${plain(plan.dailyMinor)} a day makes it last to '
              '${day(plan.lastDay)}.'
        : plan.spareMinor > 0
        ? 'Leaves ${plain(plan.spareMinor)} spare.'
        : 'A little kept back helps a lean week.';
    final chosen = _chosenMinor;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Money in · from ${widget.from}',
              style: theme.textTheme.bodyMedium!.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formatMoney(Money(widget.arrivalMinor)),
              style: AppTypography.amount(
                size: 32,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(intro, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (final bill in plan.bills) ...[
                    ListTile(
                      title: Text(bill.name),
                      subtitle: Text('Due ${shortDate(bill.due)}'),
                      trailing: Text(plain(bill.amountMinor)),
                    ),
                    const Divider(height: 1),
                  ],
                  if (plan.bufferMinor > 0) ...[
                    ListTile(
                      title: const Text('Kept back'),
                      subtitle: const Text('For a lean day'),
                      trailing: Text(plain(plan.bufferMinor)),
                    ),
                    const Divider(height: 1),
                  ],
                  ListTile(
                    key: const Key('make-it-last-daily'),
                    title: Text('Each day until ${shortDate(plan.lastDay)}'),
                    subtitle: Text(_days(plan.days)),
                    trailing: Text(
                      plain(plan.dailyMinor),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              note,
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.textMuted,
              ),
            ),
            if (_changing) ...[
              const SizedBox(height: 12),
              TextField(
                key: const Key('make-it-last-amount'),
                controller: _daily,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Each day',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('make-it-last-use'),
              onPressed: _saving || chosen == null ? null : () => _use(chosen),
              child: Text(_changing ? 'Save' : 'Use this plan'),
            ),
            if (!_changing)
              TextButton(
                key: const Key('make-it-last-change'),
                onPressed: () => setState(() => _changing = true),
                child: const Text('Change the daily amount'),
              ),
          ],
        ),
      ),
    );
  }
}

String _days(int days) => days == 1 ? '1 day' : '$days days';
