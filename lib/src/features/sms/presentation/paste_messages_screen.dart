import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ujumbe/ujumbe.dart' show Direction;

import '../../../domain/time/calendar.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/format/ledger_labels.dart';
import '../../../shared/widgets/amounts_hidden.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../balances/application/balances_providers.dart';
import '../../statements/data/pdf_text_extractor.dart';
import '../application/paste_messages.dart';
import '../application/sms_capture_providers.dart';
import '../application/transaction_mapping.dart';
import '../domain/pasted_messages.dart';

/// Reads the clipboard's text. Tests swap in their own.
final clipboardTextProvider = Provider<Future<String?> Function()>(
  (ref) =>
      () async => (await Clipboard.getData(Clipboard.kTextPlain))?.text,
);

/// `1 payment`, `10 payments`.
String paymentsLabel(int n) => n == 1 ? '1 payment' : '$n payments';

/// The line under "Found 12 payments": what is new, what is already in,
/// and what was left out.
String foundSubtitle(PasteReading reading) {
  final all = reading.payments.length;
  final already = reading.alreadyIn;
  final fresh = reading.newCount;
  final parts = <String>[
    if (all > 0)
      if (already == 0)
        all == 1 ? 'It is new.' : 'All $all are new.'
      else if (fresh == 0)
        all == 1
            ? 'It is already in your records.'
            : 'All $all are already in your records.'
      else
        '$already already in your records, so $fresh '
            '${fresh == 1 ? 'is' : 'are'} new.'
    else
      'Copy M-Pesa or bank messages that confirm a payment.',
    if (reading.notPayments == 1)
      '1 message was not a payment and is left out.'
    else if (reading.notPayments > 1)
      '${reading.notPayments} messages were not payments and are left out.',
  ];
  return parts.join(' ');
}

/// iPhone: copy M-Pesa or bank messages in Messages and paste them here.
/// Read on the phone, only when Paste or Read them is tapped; the pasted
/// text is cleared once added and kept nowhere.
class PasteMessagesScreen extends ConsumerStatefulWidget {
  const PasteMessagesScreen({this.onboarding = false, super.key});

  /// At setup, where Activity is not open yet: once added, "See your
  /// money" goes on to the first look at the messages.
  final bool onboarding;

  @override
  ConsumerState<PasteMessagesScreen> createState() =>
      _PasteMessagesScreenState();
}

class _PasteMessagesScreenState extends ConsumerState<PasteMessagesScreen> {
  final _text = TextEditingController();
  var _reading = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    String? pasted;
    try {
      pasted = await ref.read(clipboardTextProvider)();
    } on PlatformException catch (error) {
      debugPrint('The clipboard could not be read: $error');
    }
    if (!mounted) return;
    if (pasted == null || pasted.trim().isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Nothing to paste. Copy a message in Messages first.',
            ),
          ),
        );
      return;
    }
    _text.text = appendPaste(_text.text, pasted);
  }

  Future<void> _read() async {
    setState(() => _reading = true);
    final PasteReading reading;
    try {
      reading = await ref
          .read(pasteReaderProvider)
          .read(_text.text, ref.read(selectedInstitutionsProvider));
    } on Object catch (error) {
      debugPrint('Pasted messages could not be read: $error');
      if (mounted) {
        setState(() => _reading = false);
        _say('The messages could not be read. Try again.');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _reading = false);
    final added = await showAppSheet<PasteAdded>(
      context: context,
      builder: (context) => _FoundSheet(reading: reading),
    );
    if (added == null || !mounted) return;
    // The text is not kept: cleared once what it held is in the records.
    _text.clear();
    if (added.summary.added > 0) categoriseAfterPaste(ref);
    final matches = await _balanceMatch(added);
    if (!mounted) return;
    await showAppSheet<void>(
      context: context,
      builder: (context) => _AddedSheet(
        added: added,
        matches: matches,
        onboarding: widget.onboarding,
      ),
    );
  }

  /// "M-Pesa now matches its newest message: 33,069." when it does.
  Future<String?> _balanceMatch(PasteAdded added) async {
    final newest = added.newestBalance;
    if (newest == null) return null;
    try {
      final overview = await ref.refresh(balancesOverviewProvider.future);
      final account = overview.accounts
          .where(
            (a) =>
                a.account.institutionId == newest.institutionId &&
                a.opening.currency == newest.currency &&
                a.walletMinor == newest.balanceMinor,
          )
          .firstOrNull;
      if (account == null || !mounted) return null;
      final amount = shownMoney(
        context,
        newest.balanceMinor,
        currency: newest.currency,
      );
      return '${account.account.name} now matches its newest message: '
          '$amount.';
    } on Object catch (error) {
      debugPrint('Balances could not be checked after a paste: $error');
      return null;
    }
  }

  void _say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final count = splitPastedMessages(_text.text).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Paste messages')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Layout.gutter,
            8,
            Layout.gutter,
            Layout.screenBottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'In Messages, press and hold an M-Pesa message, tap Copy, then '
                'paste it below. You can paste many at once.',
                style: theme.textTheme.bodyLarge!.copyWith(
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('paste-box'),
                controller: _text,
                minLines: 6,
                maxLines: 10,
                keyboardType: TextInputType.multiline,
                // What is pasted is money: the keyboard learns none of it.
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
                style: theme.textTheme.bodySmall,
                decoration: const InputDecoration(
                  hintText: 'Paste M-Pesa messages here',
                  labelText: 'Pasted messages',
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        pastedCountLabel(count),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  PillButton(
                    key: const Key('paste-button'),
                    label: 'Paste',
                    icon: Icons.content_paste_outlined,
                    tooltip: 'Paste what you copied',
                    onPressed: _paste,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Notice(
                'Only what you paste is read, here on this iPhone. Nothing else '
                'in your Messages is touched, and nothing leaves the phone.',
                icon: Icons.lock_outline,
              ),
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('paste-read'),
                onPressed: count == 0 || _reading ? null : _read,
                child: const Text('Read them'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Found 12 payments": what the paste holds, and Add.
class _FoundSheet extends ConsumerStatefulWidget {
  const _FoundSheet({required this.reading});

  final PasteReading reading;

  @override
  ConsumerState<_FoundSheet> createState() => _FoundSheetState();
}

class _FoundSheetState extends ConsumerState<_FoundSheet> {
  static const _firstShown = 4;
  var _all = false;
  var _adding = false;
  var _failed = false;

  Future<void> _add() async {
    setState(() {
      _adding = true;
      _failed = false;
    });
    try {
      final added = await ref
          .read(pasteReaderProvider)
          .add(widget.reading, ref.read(selectedInstitutionsProvider));
      if (mounted) Navigator.of(context).pop(added);
    } on Object catch (error) {
      debugPrint('Pasted payments could not be added: $error');
      if (mounted) {
        setState(() {
          _adding = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final reading = widget.reading;
    final payments = reading.payments;
    final shown = _all ? payments : payments.take(_firstShown).toList();
    final fresh = reading.newCount;
    return SheetBody(
      title: payments.isEmpty
          ? 'No payments found'
          : 'Found ${paymentsLabel(payments.length)}',
      subtitle: foundSubtitle(reading),
      children: [
        if (payments.isNotEmpty)
          Card(
            child: Column(
              children: [
                for (final (i, p) in shown.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  _PaymentRow(p),
                ],
              ],
            ),
          ),
        if (payments.length > _firstShown && !_all)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('paste-show-all'),
              onPressed: () => setState(() => _all = true),
              child: Text('Show all ${payments.length}'),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Each is read like a message that arrives through Shortcuts: same '
          'categories, same balance check.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (_failed) ...[
          Text(
            'They could not be added. Try again.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
        ],
        if (fresh > 0)
          FilledButton(
            key: const Key('paste-add'),
            onPressed: _adding ? null : _add,
            child: Text('Add ${paymentsLabel(fresh)}'),
          )
        else
          FilledButton(
            key: const Key('paste-found-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow(this.payment);

  final PastedPayment payment;

  @override
  Widget build(BuildContext context) {
    final colors = PesaColors.of(context);
    final parsed = payment.parsed;
    final incoming = parsed.direction == Direction.incoming;
    final kind = transactionKindOf(parsed);
    final day = CalendarDate.local(parsed.time);
    final when =
        '${weekdayName(day).substring(0, 3)} ${shortDate(day)}, '
        '${formatTime(parsed.time)}';
    final amount = shownMoney(
      context,
      payment.amountMinor,
      currency: parsed.currency,
    );
    final value = payment.alreadyIn
        ? '${incoming ? '+' : '-'}$amount · Already in'
        : '${incoming ? '+' : '-'}$amount';
    return readAsAmount(
      value,
      LabelValueRow(
        label: parsed.counterparty ?? kindLabel(kind),
        detail: '$when · ${incoming ? 'Money in' : kindLabel(kind)}',
        value: value,
        valueColor: incoming && !payment.alreadyIn ? colors.successText : null,
      ),
    );
  }
}

/// "10 payments added", once the paste is in the records.
class _AddedSheet extends StatelessWidget {
  const _AddedSheet({
    required this.added,
    required this.matches,
    required this.onboarding,
  });

  final PasteAdded added;
  final String? matches;
  final bool onboarding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final n = added.summary.added;
    return SheetBody(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.check_circle_outline, color: colors.successText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      n == 0
                          ? 'Nothing new added'
                          : '${paymentsLabel(n)} added',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  if (matches != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      matches!,
                      style: theme.textTheme.bodyMedium!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'The text you pasted is cleared from this screen and is not kept.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('paste-more'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Paste more'),
              ),
            ),
            const SizedBox(width: Layout.cardGap),
            Expanded(
              child: FilledButton(
                key: const Key('paste-see'),
                onPressed: () {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  router.go(
                    onboarding
                        ? AppRoutes.onboardingFirstInsight
                        : AppRoutes.activity,
                  );
                },
                child: Text(
                  onboarding ? 'See your money' : 'See them in Activity',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// My accounts on iPhone, under M-Pesa: Paste messages, for messages
/// Shortcuts missed, beside Import a statement.
class PasteMessagesRows extends ConsumerWidget {
  const PasteMessagesRows({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(top: Layout.cardGap),
    child: Card(
      child: Column(
        children: [
          ListTile(
            key: const Key('accounts-paste'),
            title: const Text('Paste messages'),
            subtitle: const Text('Add M-Pesa messages Shortcuts missed'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.pasteMessages),
          ),
          if (ref.watch(statementImportAvailableProvider)) ...[
            const Divider(height: 1),
            ListTile(
              key: const Key('accounts-import'),
              title: const Text('Import a statement'),
              subtitle: const Text('M-Pesa or bank PDF, for older history'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.importStatement),
            ),
          ],
        ],
      ),
    ),
  );
}
