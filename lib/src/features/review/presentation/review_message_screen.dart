import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/database/app_database.dart';
import '../../../domain/reader/field_values.dart';
import '../../../domain/reader/message_reading.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/format/date_labels.dart';
import '../../../theme/pesa_colors.dart';
import '../../accounts/domain/institution.dart';
import '../application/review_draft.dart';
import '../application/review_providers.dart';

/// Below this, a suggested field is marked for checking.
const _sureEnough = 0.7;

/// The colour that marks [field] in the message and in its row.
Color fieldColor(BuildContext context, ReaderField field) {
  final Color color = switch (field) {
    ReaderField.amount => Theme.of(context).colorScheme.primary,
    ReaderField.counterparty => CupertinoColors.systemBlue,
    ReaderField.date || ReaderField.time => CupertinoColors.systemGreen,
    ReaderField.balance => CupertinoColors.systemPurple,
    ReaderField.reference => CupertinoColors.systemOrange,
    ReaderField.fee => CupertinoColors.systemTeal,
    ReaderField.other => PesaColors.of(context).textMuted,
  };
  return color is CupertinoDynamicColor ? color.resolveFrom(context) : color;
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

class _ReviewMessageScreenState extends ConsumerState<ReviewMessageScreen> {
  ReviewDraft? _draft;
  var _sameWay = true;
  var _busy = false;

  Future<void> _finish(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
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
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Done'),
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
        body: const Center(child: CircularProgressIndicator.adaptive()),
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
            AdaptiveSegmented<MessageKind>(
              key: const Key('review-kind'),
              showSelectedIcon: false,
              segments: [
                (MessageKind.moneyOut, 'Money out'),
                (MessageKind.moneyIn, 'Money in'),
                if (reading.kind == MessageKind.notTransaction)
                  (MessageKind.notTransaction, 'Notice'),
              ],
              selected: draft.kind,
              onChanged: (kind) =>
                  setState(() => _draft = draft.copyWith(kind: kind)),
            ),
            if (draft.kind != MessageKind.notTransaction) ...[
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
              child: const Text('Add transaction'),
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
              child: const Text('Not a transaction'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _rows(
    ReviewDraft draft,
    MessageReading reading,
    ReviewItem item,
    Institution? institution,
  ) {
    final currency = institution?.pack.currency ?? '';
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
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
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
