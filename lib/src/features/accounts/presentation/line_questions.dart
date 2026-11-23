import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/accounts/mpesa_lines.dart';
import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/pesa_colors.dart';
import '../../review/application/review_providers.dart';
import '../application/mpesa_lines_providers.dart';
import '../application/my_accounts_providers.dart';
import '../domain/institution.dart';
import 'mpesa_lines_screen.dart' show LinesText;

/// Whether the open space reads M-Pesa itself, where the offer to split and
/// the questions about lines wait.
final readsMpesaHereProvider = Provider<AsyncValue<bool>>(
  (ref) => ref
      .watch(selectedInstitutionIdsProvider)
      .whenData((ids) => ids.contains(mpesaInstitutionId)),
);

/// `today at 13:20`, `yesterday at 08:05` or `on Thu 19 Nov at 13:20`.
String whenLabel(DateTime at, {required CalendarDate today}) {
  final day = CalendarDate.local(at);
  final heading = dayHeading(day, today: today);
  final on = day == today || day == today.addDays(-1)
      ? heading.toLowerCase()
      : 'on $heading';
  return '$on at ${formatTime(at)}';
}

/// "Needs you" rows on Home for M-Pesa lines: two lines read as one, a
/// message whose line the balance did not tell, and a SIM not seen before.
/// Each is one row with the amber dot, as today's questions are.
class LineQuestionRows extends ConsumerWidget {
  const LineQuestionRows({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only where M-Pesa itself is read; elsewhere nothing waits here.
    if (!(ref.watch(readsMpesaHereProvider).value ?? false)) {
      return const SizedBox.shrink();
    }
    final lines = ref.watch(mpesaLinesProvider).value;
    if (lines == null) return const SizedBox.shrink();
    final which = ref.watch(whichLineItemsProvider).value ?? const [];
    final sim = lines.nextSimQuestion;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lines.offersSplit && !lines.offerHidden)
          _Row(
            key: const Key('home-two-lines'),
            title: 'Two M-Pesa lines found',
            subtitle: 'They are read as one account',
            onTap: () => context.push(AppRoutes.myAccounts),
          ),
        if (which.isNotEmpty)
          _Row(
            key: const Key('home-which-line'),
            title: 'Which line was this?',
            subtitle: which.length == 1
                ? 'One M-Pesa payment'
                : '${which.length} M-Pesa payments',
            onTap: () => showAppSheet<void>(
              context: context,
              builder: (_) => WhichLineSheet(item: which.first),
            ),
          ),
        if (lines.skipNote == SkipNote.due) LineSkipNote(lines: lines),
        if (sim != null)
          _Row(
            key: const Key('home-same-line'),
            title: 'Is this the same line as ${sim.$2.label}?',
            subtitle: 'A SIM not seen before sent M-Pesa messages',
            onTap: () => showAppSheet<void>(
              context: context,
              builder: (_) => const SameLineSheet(),
            ),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: ListTile(
          leading: Icon(Icons.circle, size: 10, color: colors.warning),
          minLeadingWidth: 10,
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Icon(Icons.chevron_right, color: colors.textMuted),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// What a waiting message was: `You paid Sunrise Cafe 300 today at
/// 13:20.`
String paymentLine(
  BuildContext context,
  ReviewItem item, {
  required CalendarDate today,
}) {
  final body = item.body ?? '';
  final parsed =
      SmsParser(
        institutionCatalogue
            .where((i) => i.id == mpesaInstitutionId)
            .map((i) => i.pack),
      ).parse(
        SmsMessage(
          sender: item.sender,
          body: body,
          receivedAt: item.receivedAt,
        ),
      );
  if (parsed is! ParsedTransaction) {
    return 'An M-Pesa message ${whenLabel(item.receivedAt, today: today)}.';
  }
  final amount = shownMoney(context, parsed.amountMinor, withCurrency: false);
  final who = parsed.counterparty;
  final when = whenLabel(parsed.time, today: today);
  return parsed.direction == Direction.incoming
      ? (who == null
            ? 'You received $amount $when.'
            : '$who sent you $amount $when.')
      : (who == null
            ? 'You paid $amount $when.'
            : 'You paid $who $amount $when.');
}

/// "Which line was this?": the payment and its time, the lines with their
/// balances, and a switch to stop being asked.
class WhichLineSheet extends ConsumerStatefulWidget {
  const WhichLineSheet({required this.item, super.key});

  final ReviewItem item;

  @override
  ConsumerState<WhichLineSheet> createState() => _WhichLineSheetState();
}

class _WhichLineSheetState extends ConsumerState<WhichLineSheet> {
  var _busy = false;

  Future<void> _answer(String lineId) async {
    setState(() => _busy = true);
    await ref
        .read(mpesaLineRoutingProvider)
        .answerWhichLine(widget.item, lineId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final lines = ref.watch(mpesaLinesProvider).value ?? MpesaLines.empty;
    final today = CalendarDate.local(ref.watch(clockProvider)());
    return SheetBody(
      title: 'Which line was this?',
      subtitle: paymentLine(context, widget.item, today: today),
      children: [
        Card(
          child: Column(
            children: [
              for (final (i, line) in lines.tracked.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  key: Key('which-line-${line.id}'),
                  enabled: !_busy,
                  title: Text(line.label),
                  subtitle: line.balanceMinor == null
                      ? null
                      : Text(
                          'Balance '
                          '${shownMoney(context, line.balanceMinor!, withCurrency: false)}',
                        ),
                  trailing: Icon(Icons.chevron_right, color: colors.textMuted),
                  onTap: () => _answer(line.id),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'The balance in the message did not say which.',
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          key: const Key('which-line-stop'),
          contentPadding: EdgeInsets.zero,
          value: !(ref.watch(askWhichLineProvider).value ?? true),
          onChanged: (stop) async {
            await ref.read(askWhichLineProvider.notifier).set(!stop);
            if (stop && context.mounted) Navigator.of(context).pop();
          },
          title: const Text("Don't ask me again"),
          subtitle: const Text('Unsure ones go to Not yet sorted'),
        ),
      ],
    );
  }
}

/// "Is this the same line as My line?", for a SIM not seen before whose
/// first message carried on from no line's balance.
class SameLineSheet extends ConsumerStatefulWidget {
  const SameLineSheet({super.key});

  @override
  ConsumerState<SameLineSheet> createState() => _SameLineSheetState();
}

class _SameLineSheetState extends ConsumerState<SameLineSheet> {
  var _busy = false;

  Future<void> _answer(NewSim sim, MpesaLine line, {required bool same}) async {
    setState(() => _busy = true);
    await ref
        .read(mpesaLineRoutingProvider)
        .answerSim(sim.sim, line.id, same: same);
    if (!mounted) return;
    // Asked about the next line, or settled.
    final next = ref.read(mpesaLinesProvider).value?.nextSimQuestion;
    if (next == null || next.$1.sim != sim.sim) {
      Navigator.of(context).pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final question = ref.watch(mpesaLinesProvider).value?.nextSimQuestion;
    if (question == null) return const SheetBody(children: []);
    final (sim, line) = question;
    final today = CalendarDate.local(ref.watch(clockProvider)());
    String day(DateTime? at) => at == null
        ? ''
        : '${dayHeading(CalendarDate.local(at), today: today)} '
              '${formatTime(at)}';
    Widget row(String title, DateTime? at, int? balance) => ListTile(
      title: Text(title),
      subtitle: at == null ? null : Text(day(at)),
      trailing: balance == null
          ? null
          : Text(
              shownMoney(context, balance, withCurrency: false),
              style: theme.textTheme.titleMedium,
            ),
    );
    return SheetBody(
      title: 'Is this the same line as ${line.label}?',
      subtitle: 'Pesa Clarity has not seen this SIM before.',
      children: [
        Card(
          child: Column(
            children: [
              row(
                '${line.label}, last balance',
                line.balanceAt,
                line.balanceMinor,
              ),
              const Divider(height: 1),
              row(
                'This SIM, first balance',
                sim.firstAt,
                sim.firstBalanceMinor,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'If it is, its messages carry on in ${line.label}. If not, it '
          'starts as a new line.',
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        ButtonPair(
          primary: FilledButton(
            key: const Key('same-line-yes'),
            onPressed: _busy ? null : () => _answer(sim, line, same: true),
            child: const Text('Same line'),
          ),
          secondary: OutlinedButton(
            key: const Key('same-line-no'),
            onPressed: _busy ? null : () => _answer(sim, line, same: false),
            child: const Text('A new line'),
          ),
        ),
      ],
    );
  }
}

/// The quiet note, once, when a message from a line the person stopped
/// tracking is first skipped. Later ones are skipped without a note; M-Pesa
/// lines says how many lines are not tracked.
class LineSkipNote extends ConsumerWidget {
  const LineSkipNote({required this.lines, super.key});

  final MpesaLines lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final name = lines.line(lines.skippedLineId ?? '')?.label ?? 'a line';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        key: const Key('line-skip-note'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                LinesText.skipped(name),
                style: theme.textTheme.bodyMedium!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  key: const Key('line-skip-note-ok'),
                  onPressed: () =>
                      ref.read(mpesaLinesProvider.notifier).skipNoteSeen(),
                  child: const Text('OK'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
