import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/contacts_repository.dart';
import '../../../domain/documents/document_settings.dart';
import '../../../domain/documents/receipt.dart';
import '../../../domain/enums.dart';
import '../../../domain/people/phone_number.dart';
import '../../../domain/people/reminder_text.dart';
import '../../../theme/pesa_colors.dart';
import '../../currency/application/currency_controller.dart';
import '../../people/presentation/remind_sheet.dart';
import '../../reminders/application/business_reminders.dart';
import '../../sales/presentation/pay_sheet.dart';
import '../application/document_providers.dart';
import '../application/receipt_pdf.dart';

/// After a sale: "Sale saved", the receipt, and how to send it. Also opens
/// later for any sale.
Future<void> showReceiptSheet(
  BuildContext context,
  int saleId, {
  bool justSaved = true,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: _ReceiptSheet(saleId, justSaved: justSaved),
      ),
    ),
  ),
);

class _ReceiptSheet extends ConsumerStatefulWidget {
  const _ReceiptSheet(this.saleId, {required this.justSaved});

  final int saleId;
  final bool justSaved;

  @override
  ConsumerState<_ReceiptSheet> createState() => _ReceiptSheetState();
}

class _ReceiptSheetState extends ConsumerState<_ReceiptSheet> {
  final _number = TextEditingController();
  Receipt? _receipt;
  ReceiptFormat? _format;
  CallingCode? _code;
  SendWith _app = SendWith.whatsapp;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final receipt = await ref
        .read(receiptMakerProvider)
        .receiptFor(widget.saleId);
    final settings = await ref.read(documentSettingsProvider.future);
    final setup = await ref.read(reminderSetupProvider.future);
    final customer = receipt?.customer;
    final contact = customer == null
        ? null
        : await ref.read(contactsRepositoryProvider).byName(customer);
    if (!mounted) return;
    setState(() {
      _receipt = receipt;
      _format = settings.sendAs;
      _app = contact?.sendWith ?? setup.sendWith;
      _code = callingCodeFor(ref.read(deviceRegionProvider));
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
  }

  Future<void> _pickContact() async {
    final picked = await ref.read(contactPickerProvider).pickPhone();
    if (picked == null || !mounted) return;
    final digits = picked.number.replaceAll(RegExp(r'[^\d+]'), '');
    final match = digits.startsWith('+')
        ? callingCodes.where((c) => digits.startsWith('+${c.code}')).firstOrNull
        : null;
    setState(() {
      if (match != null) _code = match;
      _number.text = match == null
          ? picked.number.trim()
          : digits.substring(match.code.length + 1);
    });
  }

  Future<void> _send(Receipt r) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final number = _number.text.trim().isEmpty
        ? null
        : internationalNumber(_number.text, _code ?? callingCodes.first);
    setState(() => _busy = true);
    try {
      if (number != null && r.customer != null) {
        await ref
            .read(contactsRepositoryProvider)
            .save(Contact(name: r.customer!, phone: number, sendWith: _app));
      }
      final sent = await ref
          .read(receiptMakerProvider)
          .send(
            r,
            format: _format ?? ReceiptFormat.picture,
            number: number,
            app: _app,
          );
      if (!sent) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Sharing is unavailable. The receipt is copied.'),
          ),
        );
      }
      navigator.pop();
    } on Object {
      messenger.showSnackBar(
        const SnackBar(content: Text('The receipt was not made. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final r = _receipt;
    if (r == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    final ways = [
      for (final p in r.payments)
        if (p.method != SalePaymentMethod.credit) methodLabel(p.method),
    ];
    final summary = [
      '${r.currency} ${_plain(r.totalMinor)}',
      if (ways.isNotEmpty) ways.join(' + '),
      if (r.customer case final who?) 'from $who',
    ].join(' · ').replaceFirst(' · from', ' from');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: colors.success.withValues(alpha: 0.14),
              child: Icon(Icons.check, color: colors.successText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.justSaved ? 'Sale saved' : 'Receipt',
                    style: theme.textTheme.headlineSmall,
                  ),
                  Text(
                    summary,
                    style: theme.textTheme.bodyMedium!.copyWith(
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Center(child: ReceiptCard(r)),
        const SizedBox(height: 16),
        Text(
          'Send as',
          style: theme.textTheme.bodyMedium!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final f in ReceiptFormat.values)
              ChoiceChip(
                key: Key('receipt-as-${f.name}'),
                label: Text(f.label),
                selected: _format == f,
                onSelected: (_) => setState(() => _format = f),
              ),
          ],
        ),
        const SizedBox(height: 12),
        PhoneField(
          code: _code ?? callingCodes.first,
          controller: _number,
          label: 'To (optional)',
          onCode: (c) => setState(() => _code = c),
          onPick: _pickContact,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 6),
        Text(
          _format == ReceiptFormat.text && _number.text.trim().isNotEmpty
              ? 'Opens ${_app.label} with the receipt filled in.'
              : 'Filled in when we know the customer. Leave it empty to '
                    'choose in the app.',
          style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('receipt-share'),
          onPressed: _busy ? null : () => _send(r),
          child: const Text('Share receipt'),
        ),
        const SizedBox(height: 6),
        Text(
          'Made on this phone. Opens WhatsApp, SMS or any app you choose.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
        ),
        TextButton(
          key: const Key('receipt-not-now'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Not now', style: TextStyle(color: colors.textMuted)),
        ),
      ],
    );
  }
}

/// A small picture of the receipt, as it will look.
class ReceiptCard extends StatelessWidget {
  const ReceiptCard(this.receipt, {super.key});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final r = receipt;
    String plain(int minor) => formatMoney(Money(minor), withCurrency: false);
    final small = theme.textTheme.bodySmall!;
    Widget dashed() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          for (var i = 0; i < 30; i++)
            Expanded(
              child: Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                color: colors.border,
              ),
            ),
        ],
      ),
    );
    return Container(
      key: const Key('receipt-card'),
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Text(r.business, style: theme.textTheme.titleSmall),
          Text(
            'Receipt ${r.number} · ${receiptWhen(r.at)}',
            style: small.copyWith(color: colors.textMuted),
          ),
          dashed(),
          for (final l in r.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(
                children: [
                  Expanded(child: Text(l.label(plain), style: small)),
                  Text(
                    plain(l.totalMinor),
                    style: small.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          dashed(),
          Row(
            children: [
              Expanded(child: Text('Total', style: theme.textTheme.titleSmall)),
              Text(
                '${r.currency} ${plain(r.totalMinor)}',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colors.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              receiptPaidLine(r, methodLabel, plain),
              style: small.copyWith(color: colors.successText),
            ),
          ),
        ],
      ),
    );
  }
}
