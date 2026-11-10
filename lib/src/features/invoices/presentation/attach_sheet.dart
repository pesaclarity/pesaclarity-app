import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../../documents/application/document_providers.dart';

/// A document to attach, and the cost line it adds when charged to the
/// client.
typedef Attached = ({
  PickedDocument file,
  String? costName,
  int? costMinor,
  bool recordCost,
});

/// Attach documents from the phone's files: receipts for costs, the eTIMS
/// invoice, a contract. Returns what to attach, or null.
Future<List<Attached>?> showAttachSheet(BuildContext context) =>
    showAppSheet<List<Attached>>(
      context: context,
      builder: (context) => const _AttachSheet(),
    );

class _Picked {
  _Picked(this.file)
    : name = TextEditingController(
        text: file.name.replaceFirst(RegExp(r'\.[A-Za-z0-9]+$'), ''),
      );

  final PickedDocument file;
  final TextEditingController name;
  final amount = TextEditingController();
  var charge = false;
  var record = false;

  void dispose() {
    name.dispose();
    amount.dispose();
  }
}

class _AttachSheet extends ConsumerStatefulWidget {
  const _AttachSheet();

  @override
  ConsumerState<_AttachSheet> createState() => _AttachSheetState();
}

class _AttachSheetState extends ConsumerState<_AttachSheet> {
  final _picked = <_Picked>[];

  @override
  void dispose() {
    for (final p in _picked) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final files = await ref.read(documentPickerProvider).pickDocuments();
    if (!mounted || files.isEmpty) return;
    setState(() => _picked.addAll(files.map(_Picked.new)));
  }

  Future<void> _photo() async {
    try {
      final photo = await ref.read(documentPickerProvider).takePhoto();
      if (!mounted || photo == null) return;
      setState(() => _picked.add(_Picked(photo)));
    } on PlatformException {
      if (mounted) {
        showNote(
          context,
          'The camera did not open. Choose a file on this phone instead.',
        );
      }
    }
  }

  static String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).ceil()} KB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final muted = theme.textTheme.bodySmall!.copyWith(color: colors.textMuted);
    String plain(int minor) => formatMoney(Money(minor), withCurrency: false);

    return SheetBody(
      title: 'Attach a document',
      subtitle:
          'Receipts for costs, the eTIMS invoice from the KRA site, a '
          'contract. They go after the invoice in the same PDF.',
      children: [
        Card(
          child: ListTile(
            key: const Key('attach-files'),
            leading: const Icon(Icons.folder_open_outlined),
            title: const Text('Files on this phone'),
            subtitle: Text(
              'PDF or picture, such as one saved from email',
              style: muted,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pick,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            key: const Key('attach-photo'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            subtitle: Text('A paper receipt', style: muted),
            trailing: const Icon(Icons.chevron_right),
            onTap: _photo,
          ),
        ),
        for (final p in _picked) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Layout.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        p.file.mimeType == 'application/pdf'
                            ? Icons.picture_as_pdf_outlined
                            : Icons.image_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.file.name,
                              style: theme.textTheme.titleMedium,
                            ),
                            Text(_size(p.file.bytes.length), style: muted),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove ${p.file.name}',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() {
                          _picked.remove(p);
                          p.dispose();
                        }),
                      ),
                    ],
                  ),
                  SwitchListTile.adaptive(
                    key: Key('attach-charge-${p.file.name}'),
                    contentPadding: EdgeInsets.zero,
                    value: p.charge,
                    onChanged: (on) => setState(() => p.charge = on),
                    title: const Text('Charge it to the client'),
                    subtitle: p.charge
                        ? Text(
                            'Adds a cost line: ${p.name.text.trim()}'
                            '${(AmountField.amountFrom(p.amount.text) ?? 0) > 0 ? ', ${plain(AmountField.amountFrom(p.amount.text)!)}' : ''}',
                            style: muted,
                          )
                        : null,
                  ),
                  if (p.charge)
                    SwitchListTile.adaptive(
                      key: Key('attach-record-${p.file.name}'),
                      contentPadding: EdgeInsets.zero,
                      value: p.record,
                      onChanged: (on) => setState(() => p.record = on),
                      title: const Text('Record it as a business cost'),
                      subtitle: Text(
                        "If it isn't in Money already",
                        style: muted,
                      ),
                    ),
                  if (p.charge)
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            key: Key('attach-name-${p.file.name}'),
                            controller: p.name,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(
                              labelText: 'Cost',
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: AmountField(
                            key: Key('attach-amount-${p.file.name}'),
                            controller: p.amount,
                            label: 'Amount',
                            allowZero: true,
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('attach-done'),
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final p in _picked)
                    (
                      file: p.file,
                      costName: p.charge && p.name.text.trim().isNotEmpty
                          ? p.name.text.trim()
                          : null,
                      costMinor: p.charge
                          ? AmountField.amountFrom(p.amount.text)
                          : null,
                      recordCost: p.charge && p.record,
                    ),
                ]),
          child: const Text('Attach'),
        ),
        const SizedBox(height: 6),
        Text(
          'Kept encrypted on this phone with the business. Never uploaded.',
          textAlign: TextAlign.center,
          style: muted,
        ),
      ],
    );
  }
}
