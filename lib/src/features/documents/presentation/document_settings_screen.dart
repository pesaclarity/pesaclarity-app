import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/documents_repository.dart';
import '../../../domain/documents/document_settings.dart';
import '../../../theme/pesa_colors.dart';
import '../../printing/application/printing_providers.dart';
import '../../printing/presentation/receipt_printer_screen.dart';
import '../../spaces/application/spaces_providers.dart';
import '../application/document_providers.dart';

/// Receipts and invoices: the logo, business details, how to pay, the
/// M-PESA QR, KRA PIN, numbering, the receipt footer, how receipts go, and
/// how receipts and invoices look.
class DocumentSettingsScreen extends ConsumerWidget {
  const DocumentSettingsScreen({super.key});

  Future<void> _save(WidgetRef ref, DocumentSettings next) =>
      ref.read(documentSettingsProvider.notifier).save(next);

  Future<List<String>?> _fields(
    BuildContext context,
    String title,
    List<_Field> fields,
  ) => showDialog<List<String>>(
    context: context,
    builder: (context) => _FieldsDialog(title: title, fields: fields),
  );

  Future<void> _pick(WidgetRef ref, String kind) async {
    final picked = await ref.read(documentPickerProvider).pickImage();
    if (picked == null) return;
    await ref
        .read(documentsRepositoryProvider)
        .putFile(
          kind,
          name: picked.name,
          mimeType: picked.mimeType,
          bytes: picked.bytes,
          at: ref.read(clockProvider)(),
        );
    ref.invalidate(documentFileProvider(kind));
  }

  Future<void> _remove(WidgetRef ref, String kind) async {
    await ref.read(documentsRepositoryProvider).removeFile(kind);
    ref.invalidate(documentFileProvider(kind));
  }

  /// Change or remove a picture, or pick one when there is none.
  Future<void> _picture(
    BuildContext context,
    WidgetRef ref,
    String kind, {
    required bool has,
    required String removeLabel,
  }) async {
    if (!has) return _pick(ref, kind);
    final choice = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Choose another picture'),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(removeLabel),
              onTap: () => Navigator.pop(context, false),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == true) await _pick(ref, kind);
    if (choice == false) await _remove(ref, kind);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final settings = ref.watch(documentSettingsProvider).value;
    final space = ref.watch(activeSpaceProvider).name;
    final logo = ref.watch(documentFileProvider(DocumentFileKind.logo)).value;
    final qr = ref.watch(documentFileProvider(DocumentFileKind.mpesaQr)).value;
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    Widget action(String text) =>
        Text(text, style: theme.textTheme.titleMedium);

    if (settings == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }
    final s = settings;
    final name = s.nameOr(space);
    final initialsTile = ColoredBox(
      color: theme.colorScheme.primary,
      child: Center(
        child: Text(
          DocumentSettings.initials(name),
          style: theme.textTheme.titleMedium!.copyWith(
            color: theme.colorScheme.onPrimary,
          ),
        ),
      ),
    );
    Widget card(List<Widget> rows) => Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
            r,
          ],
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Receipts and invoices')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          card([
            ListTile(
              key: const Key('documents-logo'),
              contentPadding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox.square(
                  dimension: 52,
                  child: logo != null && logo.isImage
                      ? Image.memory(
                          logo.bytes,
                          fit: BoxFit.cover,
                          // A picture that will not open shows the initials.
                          errorBuilder: (_, _, _) => initialsTile,
                        )
                      : initialsTile,
                ),
              ),
              title: const Text('Logo'),
              subtitle: Text(
                'Your initials, or a photo from this phone',
                style: muted,
              ),
              trailing: Text(
                'Change',
                style: theme.textTheme.titleMedium!.copyWith(
                  color: colors.link,
                ),
              ),
              onTap: () => _picture(
                context,
                ref,
                DocumentFileKind.logo,
                has: logo != null,
                removeLabel: 'Use my initials',
              ),
            ),
          ]),
          const SizedBox(height: 12),
          card([
            ListTile(
              key: const Key('documents-details'),
              title: const Text('Business details'),
              subtitle: Text(
                [name, ?s.place, ?s.phone, ?s.email].join(' · '),
                style: muted,
              ),
              trailing: action('Edit'),
              onTap: () async {
                final v = await _fields(context, 'Business details', [
                  _Field('Name', name),
                  _Field('Place', s.place),
                  _Field('Phone', s.phone, keyboard: TextInputType.phone),
                  _Field(
                    'Email',
                    s.email,
                    keyboard: TextInputType.emailAddress,
                  ),
                ]);
                if (v == null) return;
                await _save(
                  ref,
                  s.copyWith(
                    business: () => v[0].isEmpty || v[0] == space ? null : v[0],
                    place: () => _orNull(v[1]),
                    phone: () => _orNull(v[2]),
                    email: () => _orNull(v[3]),
                  ),
                );
              },
            ),
            ListTile(
              key: const Key('documents-pay'),
              title: const Text('How to pay'),
              subtitle: Text(
                s.payLine ?? 'Till or Paybill, and bank',
                style: muted,
              ),
              trailing: action('Edit'),
              onTap: () async {
                final v = await _fields(context, 'How to pay', [
                  _Field(
                    'Till or Paybill',
                    s.till,
                    hint: 'Such as Till 000000, or Paybill 000000 account 123',
                  ),
                  _Field(
                    'Bank details',
                    s.bank,
                    hint: 'Bank, account name and number',
                  ),
                ]);
                if (v == null) return;
                await _save(
                  ref,
                  s.copyWith(
                    till: () => _orNull(v[0]),
                    bank: () => _orNull(v[1]),
                  ),
                );
              },
            ),
            ListTile(
              key: const Key('documents-qr'),
              title: const Text('M-PESA QR on invoices'),
              subtitle: Text(
                'Your QR from the M-PESA business app',
                style: muted,
              ),
              trailing: action(qr == null ? 'Add' : 'Change'),
              onTap: () => _picture(
                context,
                ref,
                DocumentFileKind.mpesaQr,
                has: qr != null,
                removeLabel: 'Leave the QR off',
              ),
            ),
            ListTile(
              key: const Key('documents-kra'),
              title: const Text('KRA PIN'),
              subtitle: Text(
                s.kraPin == null ? 'Show on documents' : s.kraPin!,
                style: muted,
              ),
              trailing: action(s.showKraPin && s.kraPin != null ? 'On' : 'Off'),
              onTap: () async {
                final v = await _fields(context, 'KRA PIN', [
                  _Field(
                    'KRA PIN',
                    s.kraPin,
                    hint: 'Shows on documents once added',
                  ),
                ]);
                if (v == null) return;
                final pin = _orNull(v[0]);
                await _save(
                  ref,
                  s.copyWith(kraPin: () => pin, showKraPin: pin != null),
                );
              },
            ),
            ListTile(
              key: const Key('documents-numbering'),
              title: const Text('Numbering'),
              subtitle: Text(
                '${s.numberLabel(space, s.nextReceipt)} next',
                style: muted,
              ),
              trailing: action(s.prefixFor(space)),
              onTap: () async {
                final v = await _fields(context, 'Numbering', [
                  _Field(
                    'Before each number',
                    s.prefixFor(space),
                    hint: 'Such as VS-',
                  ),
                ]);
                if (v == null) return;
                await _save(ref, s.copyWith(prefix: () => _orNull(v[0])));
              },
            ),
          ]),
          const SizedBox(height: 12),
          card([
            ListTile(
              key: const Key('documents-footer'),
              title: const Text('Receipt footer'),
              subtitle: Text(
                s.footer.isEmpty ? 'None' : s.footer,
                style: muted,
              ),
              trailing: action('Edit'),
              onTap: () async {
                final v = await _fields(context, 'Receipt footer', [
                  _Field('Footer', s.footer),
                ]);
                if (v == null) return;
                await _save(ref, s.copyWith(footer: v[0]));
              },
            ),
            SwitchListTile(
              key: const Key('documents-offer'),
              title: const Text('Offer a receipt after each sale'),
              value: s.offerReceipt,
              onChanged: (on) => _save(ref, s.copyWith(offerReceipt: on)),
            ),
            Consumer(
              builder: (context, ref, _) {
                final printer = ref.watch(printerSettingsProvider).value;
                return ListTile(
                  key: const Key('documents-printer'),
                  title: const Text('Receipt printer'),
                  subtitle: Text(
                    printer?.name == null
                        ? 'A Bluetooth printer at your counter'
                        : '${printer!.name} · ${printer.paperMm} mm',
                    style: muted,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ReceiptPrinterScreen(),
                    ),
                  ),
                );
              },
            ),
            ListTile(
              key: const Key('documents-send-as'),
              title: const Text('Send receipts as'),
              subtitle: Text('Picture, PDF or text', style: muted),
              trailing: action(s.sendAs.label),
              onTap: () async {
                final f = await showModalBottomSheet<ReceiptFormat>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final f in ReceiptFormat.values)
                          ListTile(
                            key: Key('send-as-${f.name}'),
                            title: Text(f.label),
                            trailing: s.sendAs == f
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => Navigator.pop(context, f),
                          ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
                if (f != null) await _save(ref, s.copyWith(sendAs: f));
              },
            ),
          ]),
          const SizedBox(height: 12),
          card([
            ListTile(
              key: const Key('documents-receipt-colour'),
              title: const Text('Receipt colour'),
              subtitle: Text(
                'Black and white suits a till printer',
                style: muted,
              ),
              trailing: action(s.receiptColour.label),
              onTap: () async {
                final c = await _choose(
                  context,
                  ReceiptColour.values,
                  s.receiptColour,
                  (c) => c.label,
                  'receipt-colour',
                );
                if (c != null) await _save(ref, s.copyWith(receiptColour: c));
              },
            ),
            ListTile(
              key: const Key('documents-invoice-header'),
              title: const Text('Invoice header'),
              subtitle: Text('Across the top of the first page', style: muted),
              trailing: action(s.invoiceHeader.label),
              onTap: () async {
                final h = await _choose(
                  context,
                  InvoiceHeader.values,
                  s.invoiceHeader,
                  (h) => h.label,
                  'invoice-header',
                );
                if (h != null) await _save(ref, s.copyWith(invoiceHeader: h));
              },
            ),
            SwitchListTile(
              key: const Key('documents-signature'),
              title: const Text('Space to sign and stamp invoices'),
              value: s.signature,
              onChanged: (on) => _save(ref, s.copyWith(signature: on)),
            ),
            SwitchListTile(
              key: const Key('documents-branding'),
              title: const Text('Made with Pesa Clarity, at the foot'),
              subtitle: Text('On invoices and statements', style: muted),
              value: s.branding,
              onChanged: (on) => _save(ref, s.copyWith(branding: on)),
            ),
          ]),
          const SizedBox(height: 12),
          Text(
            'Receipts and invoices are made on this phone and never sent to '
            'us. They are business documents, not eTIMS tax invoices.',
            style: theme.textTheme.bodySmall!.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

String? _orNull(String v) => v.trim().isEmpty ? null : v.trim();

/// One of [values], picked from a sheet with [current] ticked.
Future<T?> _choose<T extends Enum>(
  BuildContext context,
  List<T> values,
  T current,
  String Function(T) label,
  String key,
) => showModalBottomSheet<T>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final v in values)
          ListTile(
            key: Key('$key-${v.name}'),
            title: Text(label(v)),
            trailing: v == current ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, v),
          ),
        const SizedBox(height: 8),
      ],
    ),
  ),
);

class _Field {
  const _Field(this.label, this.initial, {this.hint, this.keyboard});

  final String label;
  final String? initial;
  final String? hint;
  final TextInputType? keyboard;
}

class _FieldsDialog extends StatefulWidget {
  const _FieldsDialog({required this.title, required this.fields});

  final String title;
  final List<_Field> fields;

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final _controllers = [
    for (final f in widget.fields) TextEditingController(text: f.initial ?? ''),
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, f) in widget.fields.indexed)
            TextField(
              key: Key('field-${f.label}'),
              controller: _controllers[i],
              keyboardType: f.keyboard,
              textCapitalization: f.keyboard == null
                  ? TextCapitalization.sentences
                  : TextCapitalization.none,
              decoration: InputDecoration(
                labelText: f.label,
                helperText: f.hint,
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        key: const Key('fields-save'),
        onPressed: () => Navigator.pop(context, [
          for (final c in _controllers) c.text.trim(),
        ]),
        child: const Text('Save'),
      ),
    ],
  );
}
