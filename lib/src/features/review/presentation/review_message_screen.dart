import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/ledger/balances.dart';
import '../../../domain/reader/field_values.dart';
import '../../../domain/reader/message_reading.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/domain/institution.dart';
import '../../activity/application/activity_providers.dart';
import '../../balances/application/balances_providers.dart';
import '../../balances/presentation/add_account_sheet.dart';
import '../../balances/presentation/balance_text.dart';
import '../application/review_draft.dart';
import '../application/review_providers.dart';

/// The account a transfer message most likely names: one whose name or
/// institution it prints, else a day-to-day account with messages, else
/// the first.
Account likelyOtherAccount(List<Account> others, String body) {
  String plain(String text) =>
      text.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');
  final text = plain(body);
  for (final a in others) {
    final names = [a.name, ?a.institutionId].map(plain);
    if (names.any((n) => n.length > 2 && text.contains(n))) return a;
  }
  return others
          .where(
            (a) =>
                a.institutionId != null &&
                !savingsAccountTypes.contains(a.type),
          )
          .firstOrNull ??
      others.first;
}

/// Below this, a suggested field is marked for checking.
const _sureEnough = 0.7;

/// The colour that marks [field] in the message and in its row, from the
/// app's palette.
Color fieldColor(BuildContext context, ReaderField field) {
  final scheme = Theme.of(context).colorScheme;
  final colors = PesaColors.of(context);
  return switch (field) {
    ReaderField.amount => scheme.primary,
    ReaderField.counterparty => colors.markBlue,
    ReaderField.date || ReaderField.time => colors.successText,
    ReaderField.reference => colors.warning,
    ReaderField.balance => colors.markPurple,
    ReaderField.fee => colors.markTeal,
    ReaderField.other => colors.textMuted,
  };
}

/// One message: the text with its fields marked, the suggested values to
/// confirm or change, and the choice to read the same layout without
/// asking next time.
class ReviewMessageScreen extends ConsumerStatefulWidget {
  const ReviewMessageScreen({required this.itemId, super.key});

  final int itemId;

  @override
  ConsumerState<ReviewMessageScreen> createState() =>
      _ReviewMessageScreenState();
}

/// What the person says a message is.
enum _Choice { moneyOut, moneyIn, myAccounts, notice }

class _ReviewMessageScreenState extends ConsumerState<ReviewMessageScreen> {
  ReviewDraft? _draft;
  var _sameWay = true;
  var _busy = false;

  /// Money moved between the person's own accounts.
  var _mine = false;

  /// Whether the message's account is the one the money left.
  bool? _messageIsFrom;
  int? _otherAccountId;
  int? _feeMinor;

  Future<void> _finish(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await action();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(done)));
      navigator.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _editText(
    String title,
    String? value, {
    bool number = false,
  }) {
    final controller = TextEditingController(text: value ?? '');
    return showAdaptiveDialog<String>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(title),
        content: TextField(
          key: const Key('review-edit-field'),
          controller: controller,
          autofocus: true,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
        ),
        actions: [
          DialogAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          DialogAction(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _editDate(ReviewDraft draft, DateTime receivedAt) async {
    final current = draft.date ?? CalendarDate.local(receivedAt);
    final picked = await pickDate(
      context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(current.year - 2),
      lastDate: DateTime(current.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    final minutes = draft.minutes ?? 0;
    final time = await pickTime(
      context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    setState(
      () => _draft = draft.copyWith(
        date: CalendarDate(picked.year, picked.month, picked.day),
        minutes: time == null ? draft.minutes : time.hour * 60 + time.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(pendingReviewProvider).value;
    final item = items?.where((i) => i.id == widget.itemId).firstOrNull;
    final reading = ref.watch(reviewReadingProvider(widget.itemId));
    if (item == null || reading == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Check this message')),
        body: const LoadingView(),
      );
    }
    final draft = _draft ??= ReviewDraft.fromReading(reading);
    final institution = ref
        .watch(institutionCatalogueProvider)
        .where((i) => i.id == item.institutionId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Check this message')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            _MessageBubble(item.body ?? '', reading),
            const SizedBox(height: 4),
            Text(
              '${institution?.name ?? item.sender} · '
              '${longDate(CalendarDate.local(item.receivedAt))}, '
              '${formatTime(item.receivedAt)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            AdaptiveSegmented<_Choice>(
              key: const Key('review-kind'),
              showSelectedIcon: false,
              segments: [
                (_Choice.moneyOut, 'Money out'),
                (_Choice.moneyIn, 'Money in'),
                (_Choice.myAccounts, BalanceText.myAccounts),
                if (reading.kind == MessageKind.notTransaction)
                  (_Choice.notice, 'Notice'),
              ],
              selected: _mine
                  ? _Choice.myAccounts
                  : switch (draft.kind) {
                      MessageKind.moneyOut => _Choice.moneyOut,
                      MessageKind.moneyIn => _Choice.moneyIn,
                      MessageKind.notTransaction => _Choice.notice,
                    },
              segmentKey: (choice) => Key('review-choice-${choice.name}'),
              onChanged: (choice) => setState(() {
                _mine = choice == _Choice.myAccounts;
                final kind = switch (choice) {
                  _Choice.moneyOut => MessageKind.moneyOut,
                  _Choice.moneyIn => MessageKind.moneyIn,
                  _Choice.notice => MessageKind.notTransaction,
                  _Choice.myAccounts =>
                    draft.kind == MessageKind.notTransaction
                        ? MessageKind.moneyOut
                        : draft.kind,
                };
                _draft = draft.copyWith(kind: kind);
              }),
            ),
            if (_mine)
              ..._ownTransfer(draft, item, institution)
            else if (draft.kind != MessageKind.notTransaction) ...[
              GroupedSection(
                header: 'Suggested · tap to change',
                children: _rows(draft, reading, item, institution),
              ),
              const SizedBox(height: 12),
              Card(
                child: SwitchListTile.adaptive(
                  key: const Key('review-same-way'),
                  title: const Text('Read messages like this the same way'),
                  subtitle: Text(
                    'Saved on this phone for '
                    '${institution?.name ?? item.sender}',
                  ),
                  value: _sameWay,
                  onChanged: (on) => setState(() => _sameWay = on),
                ),
              ),
            ],
            if (!_mine) ...[
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('review-add'),
                onPressed: _busy || !draft.isComplete
                    ? null
                    : () => _finish(
                        () => ref
                            .read(reviewControllerProvider)
                            .confirm(
                              item,
                              draft,
                              reading: reading,
                              sameWay: _sameWay,
                            ),
                        'Added to Activity.',
                      ),
                child: const Text('Add a transaction'),
              ),
              const SizedBox(height: 8),
              TextButton(
                key: const Key('review-dismiss'),
                onPressed: _busy
                    ? null
                    : () => _finish(
                        () => ref.read(reviewControllerProvider).dismiss(item),
                        'Checked.',
                      ),
                child: const Text("It's not money"),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "My accounts": from which account to which, how much, the fee and
  /// when, and whether the other side is already here.
  List<Widget> _ownTransfer(
    ReviewDraft draft,
    ReviewItem item,
    Institution? institution,
  ) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final accounts = (ref.watch(activityAccountsProvider).value ?? const {})
        .values
        .toList();
    final currency = draft.currency ?? institution?.pack.currency ?? 'KES';
    int inCurrency(int hundredths) => rescaleMinor(
      hundredths,
      fromDigits: 2,
      toDigits: minorUnitDigits(currency),
    );
    // The message's account, or a stand-in until its first message makes it.
    const placeholder = -1;
    final mine = accounts
        .where((a) => a.institutionId == item.institutionId)
        .firstOrNull;
    final messageId = mine?.id ?? placeholder;
    final messageName = mine?.name ?? institution?.name ?? item.sender;
    final others = [
      for (final a in accounts)
        if (a.id != messageId) a,
    ];
    if (others.isEmpty) {
      return [
        const SizedBox(height: 12),
        const Notice(BalanceText.noOtherAccount),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => showAddAccountSheet(context),
          child: const Text(BalanceText.addAccount),
        ),
      ];
    }
    final messageIsFrom = _messageIsFrom ?? draft.kind != MessageKind.moneyIn;
    final otherId = others.any((a) => a.id == _otherAccountId)
        ? _otherAccountId!
        : likelyOtherAccount(others, item.body ?? '').id;
    final options = [
      (messageId, messageName),
      for (final a in others) (a.id, a.name),
    ];
    String nameOf(int id) =>
        options.firstWhere((o) => o.$1 == id, orElse: () => (id, '')).$2;
    final amount = draft.amountMinor == null
        ? null
        : inCurrency(draft.amountMinor!);
    final fee = _feeMinor ?? inCurrency(draft.feeMinor ?? 0);
    final when = draft.occurredAt(item.receivedAt);
    final partner = amount == null
        ? null
        : ref
              .watch(
                transferPartnerProvider((
                  otherAccountId: otherId,
                  otherIsInflow: messageIsFrom,
                  amountMinor: amount,
                  feeMinor: fee,
                  at: when,
                )),
              )
              .value;
    String money(int minor) =>
        formatMoney(Money(minor, currency: currency), withCurrency: false);
    final day = CalendarDate.local(when);
    Widget row(String label, Widget value, {VoidCallback? onTap, Key? key}) =>
        ListTile(
          key: key,
          title: Text(label),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              value,
              if (onTap != null) const Icon(Icons.chevron_right),
            ],
          ),
          onTap: onTap,
        );
    Widget pick(String name, int value, ValueChanged<int> onChanged) =>
        ChoiceMenu<int>(
          key: Key('review-own-$name'),
          name: name,
          options: options,
          value: value,
          onChanged: onChanged,
        );

    return [
      GroupedSection(
        children: [
          row(
            BalanceText.from,
            pick(
              'from',
              messageIsFrom ? messageId : otherId,
              (v) => setState(() {
                if (v == messageId) {
                  _messageIsFrom = true;
                } else {
                  _messageIsFrom = false;
                  _otherAccountId = v;
                }
              }),
            ),
          ),
          row(
            BalanceText.to,
            pick(
              'to',
              messageIsFrom ? otherId : messageId,
              (v) => setState(() {
                if (v == messageId) {
                  _messageIsFrom = false;
                } else {
                  _messageIsFrom = true;
                  _otherAccountId = v;
                }
              }),
            ),
          ),
          row(
            BalanceText.amount,
            Text(amount == null ? 'Add' : money(amount)),
            key: const Key('review-own-amount'),
            onTap: () async {
              final text = await _editText(
                BalanceText.amount,
                amount == null ? null : money(amount),
                number: true,
              );
              final minor = text == null ? null : amountMinorFrom(text);
              if (minor != null) {
                setState(() => _draft = draft.copyWith(amountMinor: minor));
              }
            },
          ),
          if (messageIsFrom)
            row(
              BalanceText.fee,
              Text(money(fee)),
              key: const Key('review-own-fee'),
              onTap: () async {
                final text = await _editText(
                  BalanceText.fee,
                  money(fee),
                  number: true,
                );
                final minor = text == null ? null : amountMinorFrom(text);
                if (minor != null) {
                  setState(() => _feeMinor = inCurrency(minor));
                }
              },
            ),
          row(
            BalanceText.date,
            Text(
              '${dayHeading(day, today: CalendarDate.local(ref.read(clockProvider)()))} ${formatTime(when)}',
            ),
            onTap: () => _editDate(draft, item.receivedAt),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Card(
        key: Key(partner == null ? 'review-own-waiting' : 'review-own-matched'),
        child: Padding(
          padding: const EdgeInsets.all(Layout.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconBadge(partner == null ? Icons.more_horiz : Icons.check),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner == null
                          ? BalanceText.waitingTitle(nameOf(otherId))
                          : BalanceText.matchedWith(nameOf(otherId)),
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      partner == null
                          ? BalanceText.waitingDetail(
                              nameOf(otherId),
                              nameOf(messageIsFrom ? messageId : otherId),
                            )
                          : BalanceText.matchedDetail(
                              '${partner.isInflow ? 'Received' : 'Sent'} '
                              '$currency ${money(partner.amountMinor)}',
                              formatTime(partner.occurredAt),
                            ),
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('review-save-transfer'),
        onPressed: _busy || amount == null || amount <= 0
            ? null
            : () => _finish(
                () => ref
                    .read(reviewControllerProvider)
                    .confirmOwnTransfer(
                      item,
                      messageIsFrom: messageIsFrom,
                      otherAccountId: otherId,
                      amountMinor: amount,
                      feeMinor: fee,
                      at: when,
                      currency: currency,
                      partnerId: partner?.id,
                    ),
                BalanceText.transferSaved,
              ),
        child: const Text(BalanceText.saveTransfer),
      ),
    ];
  }

  List<Widget> _rows(
    ReviewDraft draft,
    MessageReading reading,
    ReviewItem item,
    Institution? institution,
  ) {
    final currency = draft.currency ?? institution?.pack.currency ?? '';
    String money(int? minor) => minor == null
        ? 'Add'
        : '$currency ${formatMoney(Money(minor), withCurrency: false)}'.trim();
    final day = draft.date;
    final minutes = draft.minutes;
    final when = day == null
        ? 'Add'
        : '${longDate(day)}'
              '${minutes == null ? '' : ', ${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}'}';
    final out = draft.kind == MessageKind.moneyOut;
    return [
      _FieldRow(
        key: const Key('review-amount'),
        field: ReaderField.amount,
        label: 'Amount',
        value: money(draft.amountMinor),
        reading: reading,
        onTap: () async {
          final text = await _editText(
            'Amount',
            draft.amountMinor == null
                ? null
                : formatMoney(Money(draft.amountMinor!), withCurrency: false),
            number: true,
          );
          final minor = text == null ? null : amountMinorFrom(text);
          if (minor != null) {
            setState(() => _draft = draft.copyWith(amountMinor: minor));
          }
        },
      ),
      _FieldRow(
        key: const Key('review-party'),
        field: ReaderField.counterparty,
        label: out ? 'Paid to' : 'Received from',
        value: draft.counterparty ?? 'Add',
        reading: reading,
        onTap: () async {
          final text = await _editText(
            out ? 'Paid to' : 'Received from',
            draft.counterparty,
          );
          if (text != null && text.isNotEmpty) {
            setState(() => _draft = draft.copyWith(counterparty: text));
          }
        },
      ),
      _FieldRow(
        field: ReaderField.date,
        label: 'Date',
        value: when,
        reading: reading,
        onTap: () => _editDate(draft, item.receivedAt),
      ),
      if (draft.balanceMinor != null)
        _FieldRow(
          field: ReaderField.balance,
          label: 'Balance after',
          value: money(draft.balanceMinor),
          reading: reading,
        ),
      _FieldRow(
        field: ReaderField.reference,
        label: 'Receipt',
        value: draft.reference ?? 'Add',
        reading: reading,
        onTap: () async {
          final text = await _editText('Receipt', draft.reference);
          if (text != null && text.isNotEmpty) {
            setState(() => _draft = draft.copyWith(reference: text));
          }
        },
      ),
    ];
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.label,
    required this.value,
    required this.reading,
    this.onTap,
    super.key,
  });

  final ReaderField field;
  final String label;
  final String value;
  final MessageReading reading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final found = reading.fields[field];
    final unsure = found == null || found.confidence < _sureEnough;
    return ListTile(
      leading: Icon(Icons.circle, size: 12, color: fieldColor(context, field)),
      minLeadingWidth: 12,
      title: Text(label, style: theme.textTheme.bodySmall),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.bodyLarge),
          if (unsure && value != 'Add')
            Text(
              'Check this',
              style: theme.textTheme.labelSmall!.copyWith(
                color: colors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// The message as received, with each found field tinted in its colour.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble(this.body, this.reading);

  final String body;
  final MessageReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = reading.fields.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final spans = <InlineSpan>[];
    var at = 0;
    for (final f in fields) {
      if (f.start < at) continue;
      spans.add(TextSpan(text: body.substring(at, f.start)));
      final color = fieldColor(context, f.field);
      spans.add(
        TextSpan(
          text: f.text,
          style: TextStyle(
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      at = f.end;
    }
    spans.add(TextSpan(text: body.substring(at)));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text.rich(
          TextSpan(style: theme.textTheme.bodyMedium, children: spans),
          key: const Key('review-message'),
        ),
      ),
    );
  }
}
