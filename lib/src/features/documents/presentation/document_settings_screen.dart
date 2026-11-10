import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/documents_repository.dart';
import '../../../domain/documents/document_settings.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
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
  ) => showAdaptiveDialog<List<String>>(
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

  /// Change or remove a picture, or choose one when there is none.
  Future<void> _picture(
    BuildContext context,
    WidgetRef ref,
    String kind, {
    required String title,
    required bool has,
    required String removeLabel,
  }) async {
    if (!has) return _pick(ref, kind);
    final choice = await showAppSheet<bool>(
      context: context,
      builder: (context) => SheetBody(
        title: title,
        children: [
          GroupedSection(
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
            ],
          ),
        ],
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
    const title = Text('Receipts and invoices');

    if (settings == null) {
      return Scaffold(
        appBar: AppBar(title: title),
        body: const LoadingView(),
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
    return Scaffold(
      appBar: AppBar(title: title),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          GroupedSection(
            children: [
              ListTile(
                key: const Key('documents-logo'),
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
                trailing: const TrailingLink('Change'),
                onTap: () => _picture(
                  context,
                  ref,
                  DocumentFileKind.logo,
                  title: 'Logo',
                  has: logo != null,
                  removeLabel: 'Use my initials',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GroupedSection(
            children: [
              ListTile(
                key: const Key('documents-details'),
                title: const Text('Business details'),
                subtitle: Text(
                  [name, ?s.place, ?s.phone, ?s.email].join(' · '),
                  style: muted,
                ),
                trailing: const TrailingLink('Edit'),
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
                      business: () =>
                          v[0].isEmpty || v[0] == space ? null : v[0],
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
                trailing: const TrailingLink('Edit'),
                onTap: () async {
                  final v = await _fields(context, 'How to pay', [
                    _Field(
                      'Till or Paybill',
                      s.till,
                      hint:
                          'Such as Till 000000, or Paybill 000000 account 123',
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
                trailing: TrailingLink(qr == null ? 'Add' : 'Change'),
                onTap: () => _picture(
                  context,
                  ref,
                  DocumentFileKind.mpesaQr,
                  title: 'M-PESA QR',
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
                trailing: TrailingLink(
                  s.showKraPin && s.kraPin != null ? 'Edit' : 'Add',
                ),
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
                trailing: const TrailingLink('Edit'),
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
            ],
          ),
          const SizedBox(height: 12),
          GroupedSection(
            children: [
              ListTile(
                key: const Key('documents-footer'),
                title: const Text('Receipt footer'),
                subtitle: Text(
                  s.footer.isEmpty ? 'None' : s.footer,
                  style: muted,
                ),
                trailing: const TrailingLink('Edit'),
                onTap: () async {
                  final v = await _fields(context, 'Receipt footer', [
                    _Field('Footer', s.footer),
                  ]);
                  if (v == null) return;
                  await _save(ref, s.copyWith(footer: v[0]));
                },
              ),
              SwitchListTile.adaptive(
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
                title: const Text('Send receipts as'),
                subtitle: Text('Picture, PDF or text', style: muted),
                trailing: ChoiceMenu<ReceiptFormat>(
                  key: const Key('documents-send-as'),
                  name: 'Send receipts as',
                  options: [for (final f in ReceiptFormat.values) (f, f.label)],
                  value: s.sendAs,
                  itemKey: (f) => Key('send-as-${f.name}'),
                  onChanged: (f) => _save(ref, s.copyWith(sendAs: f)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GroupedSection(
            children: [
              ListTile(
                title: const Text('Receipt colour'),
                subtitle: Text(
                  'Black and white suits a till printer',
                  style: muted,
                ),
                trailing: ChoiceMenu<ReceiptColour>(
                  key: const Key('documents-receipt-colour'),
                  name: 'Receipt colour',
                  options: [for (final c in ReceiptColour.values) (c, c.label)],
                  value: s.receiptColour,
                  itemKey: (c) => Key('receipt-colour-${c.name}'),
                  onChanged: (c) => _save(ref, s.copyWith(receiptColour: c)),
                ),
              ),
              ListTile(
                title: const Text('Invoice header'),
                subtitle: Text(
                  'Across the top of the first page',
                  style: muted,
                ),
                trailing: ChoiceMenu<InvoiceHeader>(
                  key: const Key('documents-invoice-header'),
                  name: 'Invoice header',
                  options: [for (final h in InvoiceHeader.values) (h, h.label)],
                  value: s.invoiceHeader,
                  itemKey: (h) => Key('invoice-header-${h.name}'),
                  onChanged: (h) => _save(ref, s.copyWith(invoiceHeader: h)),
                ),
              ),
              SwitchListTile.adaptive(
                key: const Key('documents-signature'),
                title: const Text('Space to sign and stamp invoices'),
                value: s.signature,
                onChanged: (on) => _save(ref, s.copyWith(signature: on)),
              ),
              SwitchListTile.adaptive(
                key: const Key('documents-branding'),
                title: const Text('Made with Pesa Clarity, at the foot'),
                subtitle: Text('On invoices and statements', style: muted),
                value: s.branding,
                onChanged: (on) => _save(ref, s.copyWith(branding: on)),
              ),
            ],
          ),
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
  Widget build(BuildContext context) => AlertDialog.adaptive(
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
      DialogAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      DialogAction(
        key: const Key('fields-save'),
        onPressed: () => Navigator.pop(context, [
          for (final c in _controllers) c.text.trim(),
        ]),
        child: const Text('Save'),
      ),
    ],
  );
}
