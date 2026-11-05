import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/contacts_repository.dart';
import '../../../domain/people/people.dart';
import '../../../domain/people/phone_number.dart';
import '../../../domain/people/reminder_text.dart';
import '../../../domain/time/calendar.dart';
import '../../../theme/pesa_colors.dart';
import '../../currency/application/currency_controller.dart';
import '../../insights/application/report_sharer.dart';
import '../../invoices/application/invoice_providers.dart';
import '../../invoices/application/invoice_sender.dart';
import '../../lending/data/reminder_sharer.dart';
import '../../reminders/application/business_reminders.dart';
import '../../spaces/application/spaces_providers.dart';

/// Remind a customer: a message from the business's templates, which the
/// owner can change, sent with WhatsApp or SMS to their number. The owner
/// taps send in that app. Returns true once it was opened.
Future<bool?> showRemindSheet(BuildContext context, CustomerAccount customer) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: _RemindSheet(customer),
          ),
        ),
      ),
    );

class _RemindSheet extends ConsumerStatefulWidget {
  const _RemindSheet(this.customer);

  final CustomerAccount customer;

  @override
  ConsumerState<_RemindSheet> createState() => _RemindSheetState();
}

class _RemindSheetState extends ConsumerState<_RemindSheet> {
  final _message = TextEditingController();
  final _number = TextEditingController();
  String? _templateId;
  SendWith? _sendWith;
  CallingCode? _code;
  var _loaded = false;
  var _busy = false;
  var _attachInvoice = true;

  @override
  void dispose() {
    _message.dispose();
    _number.dispose();
    super.dispose();
  }

  Map<String, String?> _values(ReminderSetup setup) => reminderValues(
    widget.customer,
    business: ref.read(activeSpaceProvider).name,
    today: CalendarDate.local(ref.read(clockProvider)()),
    till: setup.till,
  );

  void _useTemplate(ReminderSetup setup, ReminderTemplate t) => setState(() {
    _templateId = t.id;
    _message.text = fillTemplate(t.text, _values(setup));
  });

  Future<void> _load(ReminderSetup setup) async {
    _loaded = true;
    final contact = await ref
        .read(contactsRepositoryProvider)
        .byName(widget.customer.name);
    if (!mounted) return;
    final region = ref.read(deviceRegionProvider);
    setState(() {
      _sendWith = contact?.sendWith ?? setup.sendWith;
      _code = callingCodeFor(region);
      final phone = contact?.phone;
      if (phone != null) {
        final match = callingCodes
            .where((c) => phone.startsWith('+${c.code}'))
            .firstOrNull;
        _code = match ?? _code;
        _number.text = match == null
            ? phone
            : phone.substring(match.code.length + 1);
      }
    });
    _useTemplate(setup, _pickTemplate(setup));
  }

  /// "Due today" on the day, "It's been a while" after two weeks, else the
  /// first.
  ReminderTemplate _pickTemplate(ReminderSetup setup) {
    final today = CalendarDate.local(ref.read(clockProvider)());
    ReminderTemplate? byId(String id) =>
        setup.templates.where((t) => t.id == id).firstOrNull;
    final c = widget.customer;
    if (c.nextDue == today) return byId('due_today') ?? setup.templates.first;
    if (c.overTwoWeeksMinor > 0) {
      return byId('a_while') ?? setup.templates.first;
    }
    return setup.templates.first;
  }

  Future<void> _pickContact() async {
    final picked = await ref.read(contactPickerProvider).pickPhone();
    if (picked == null || !mounted) return;
    setState(() {
      final number = picked.number.trim();
      final match = number.startsWith('+')
          ? callingCodes
                .where(
                  (c) => number
                      .replaceAll(RegExp(r'[^\d+]'), '')
                      .startsWith('+${c.code}'),
                )
                .firstOrNull
          : null;
      if (match != null) {
        _code = match;
        _number.text = number
            .replaceAll(RegExp(r'[^\d+]'), '')
            .substring(match.code.length + 1);
      } else {
        _number.text = number;
      }
    });
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final code = _code ?? callingCodes.first;
    final international = _number.text.trim().isEmpty
        ? null
        : internationalNumber(_number.text, code);
    final app = _sendWith ?? SendWith.whatsapp;
    final invoice = _attachInvoice ? _openInvoice() : null;
    setState(() => _busy = true);
    try {
      if (invoice != null) {
        // With the invoice attached, the share sheet takes the file and the
        // message; the owner picks the app and the person.
        if (international != null) {
          await ref
              .read(contactsRepositoryProvider)
              .save(
                Contact(
                  name: widget.customer.name,
                  phone: international,
                  sendWith: app,
                ),
              );
        }
        final sender = ref.read(invoiceSenderProvider);
        final files = await sender.files(
          await sender.docFor(invoice),
          one: true,
        );
        await ref
            .read(reportSharerProvider)
            .shareFiles(
              files,
              subject: 'Invoice ${invoice.invoice.number}',
              text: text,
            );
        navigator.pop(true);
        return;
      }
      await ref
          .read(contactsRepositoryProvider)
          .save(
            Contact(
              name: widget.customer.name,
              phone: international,
              sendWith: app,
            ),
          );
      var opened = false;
      if (international != null) {
        opened = await ref
            .read(messageLauncherProvider)
            .open(app, international, text);
      }
      if (!opened) {
        try {
          await ref.read(reminderSharerProvider).share(text);
          opened = true;
        } on PlatformException {
          await Clipboard.setData(ClipboardData(text: text));
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Sharing is unavailable. The message is copied.'),
            ),
          );
        }
      }
      navigator.pop(opened);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The customer's newest invoice still to be paid, if any.
  InvoiceView? _openInvoice() =>
      (ref.read(invoicesProvider).value ?? const <InvoiceView>[])
          .where(
            (v) =>
                v.leftMinor > 0 &&
                v.invoice.client.trim().toLowerCase() ==
                    widget.customer.name.trim().toLowerCase(),
          )
          .firstOrNull;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final setup = ref.watch(reminderSetupProvider).value;
    ref.watch(invoicesProvider);
    final invoice = _openInvoice();
    if (setup == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    if (!_loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(setup));
    }
    final app = _sendWith ?? setup.sendWith;
    final hasNumber = _number.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Remind ${widget.customer.name}',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in setup.templates)
              ChoiceChip(
                key: Key('template-${t.id}'),
                label: Text(t.name),
                selected: _templateId == t.id,
                onSelected: (_) => _useTemplate(setup, t),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('remind-message'),
          controller: _message,
          minLines: 3,
          maxLines: 6,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Message (change it for this one if you like)',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Send with',
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final s in SendWith.values)
              ChoiceChip(
                key: Key('send-with-${s.name}'),
                label: Text(s.label),
                selected: app == s,
                onSelected: (_) => setState(() => _sendWith = s),
              ),
          ],
        ),
        const SizedBox(height: 16),
        PhoneField(
          code: _code ?? callingCodes.first,
          controller: _number,
          onCode: (c) => setState(() => _code = c),
          onPick: _pickContact,
          onChanged: () => setState(() {}),
        ),
        if (invoice != null)
          CheckboxListTile(
            key: const Key('remind-attach-invoice'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _attachInvoice,
            onChanged: (on) => setState(() => _attachInvoice = on ?? false),
            title: Text('Attach invoice ${invoice.invoice.number}'),
            subtitle: Text(
              'With the invoice, you choose the app and the person.',
              style: theme.textTheme.bodySmall!.copyWith(
                color: colors.textMuted,
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          invoice != null && _attachInvoice
              ? 'Opens the share menu with the invoice and the message.'
              : hasNumber
              ? 'Opens ${app.label} with the message filled in. You tap send '
                    'there.'
              : 'Without a number, you choose the app and the person.',
          style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('remind-send'),
          onPressed: _busy ? null : _send,
          child: Text(
            hasNumber && !(invoice != null && _attachInvoice)
                ? 'Open ${app.label}'
                : 'Share',
          ),
        ),
      ],
    );
  }
}

/// A phone number with its country code, and a button for the phone's own
/// contact picker.
class PhoneField extends StatelessWidget {
  const PhoneField({
    required this.code,
    required this.controller,
    required this.onCode,
    required this.onPick,
    this.onChanged,
    this.label = 'Phone (optional)',
    super.key,
  });

  final CallingCode code;
  final TextEditingController controller;
  final ValueChanged<CallingCode> onCode;
  final VoidCallback onPick;
  final VoidCallback? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      DropdownButton<CallingCode>(
        key: const Key('phone-code'),
        value: code,
        underline: const SizedBox.shrink(),
        selectedItemBuilder: (context) => [
          for (final c in callingCodes) Center(child: Text('+${c.code}')),
        ],
        items: [
          for (final c in callingCodes)
            DropdownMenuItem(value: c, child: Text('+${c.code}  ${c.country}')),
        ],
        onChanged: (c) {
          if (c != null) onCode(c);
        },
      ),
      const SizedBox(width: 8),
      Expanded(
        child: TextField(
          key: const Key('phone-number'),
          controller: controller,
          keyboardType: TextInputType.phone,
          onChanged: (_) => onChanged?.call(),
          decoration: InputDecoration(labelText: label),
        ),
      ),
      IconButton(
        key: const Key('phone-contacts'),
        tooltip: 'Choose from contacts',
        icon: const Icon(Icons.contacts_outlined),
        onPressed: onPick,
      ),
    ],
  );
}
