import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/printing/slip.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/states.dart';
import '../application/printing_providers.dart';
import 'receipt_printer_screen.dart';

/// Where a document prints.
enum PrintOn { counter, phone }

/// Print: on the counter printer when [slip] is given (a receipt or the
/// day's summary), or on any printer the phone reaches, or as a PDF made
/// by [pdf]. [title] and [subtitle] name what prints; [name] is the file
/// name a saved PDF gets.
Future<void> showPrintSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Future<Uint8List> Function() pdf,
  required String name,
  Slip Function()? slip,
  bool fullPage = false,
}) => showAppSheet<void>(
  context: context,
  builder: (context) => _PrintSheet(
    title: title,
    subtitle: subtitle,
    pdf: pdf,
    name: name,
    slip: slip,
    fullPage: fullPage,
  ),
);

class _PrintSheet extends ConsumerStatefulWidget {
  const _PrintSheet({
    required this.title,
    required this.subtitle,
    required this.pdf,
    required this.name,
    required this.slip,
    required this.fullPage,
  });

  final String title;
  final String subtitle;
  final Future<Uint8List> Function() pdf;
  final String name;
  final Slip Function()? slip;
  final bool fullPage;

  @override
  ConsumerState<_PrintSheet> createState() => _PrintSheetState();
}

class _PrintSheetState extends ConsumerState<_PrintSheet> {
  PrintOn? _on;
  var _copies = 1;
  var _busy = false;

  Future<void> _print(PrintOn on) async {
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final printer = ref.read(slipPrinterProvider);
      if (on == PrintOn.counter) {
        await printer.onCounter(widget.slip!(), copies: _copies);
        navigator.pop();
        if (navigator.mounted) {
          showNote(
            navigator.context,
            _copies == 1 ? 'Printed.' : 'Printed $_copies copies.',
          );
        }
      } else {
        final bytes = await widget.pdf();
        navigator.pop();
        await printer.onPhone(bytes, widget.name);
      }
    } on Object {
      if (navigator.mounted) {
        showNote(
          navigator.context,
          'Turn the printer on and keep it close to the phone, then try '
          'again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setUp() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ReceiptPrinterScreen()),
    );
    if (mounted) setState(() => _on = null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(printerSettingsProvider).value;
    final supported =
        ref.watch(counterPrintingSupportedProvider).value ?? false;
    final counter = widget.slip != null && supported;
    final ready = counter && (settings?.hasPrinter ?? false);
    final on = _on ?? (ready ? PrintOn.counter : PrintOn.phone);
    final paper = settings?.paperMm ?? 58;

    Widget option(PrintOn value, String title, String detail, {Key? key}) =>
        RadioListTile<PrintOn>(
          key: key,
          value: value,
          title: Text(title),
          subtitle: Text(detail),
        );

    return RadioGroup<PrintOn>(
      groupValue: on,
      onChanged: (value) {
        if (value == PrintOn.counter && !ready) {
          _setUp();
          return;
        }
        if (value != null) setState(() => _on = value);
      },
      child: SheetBody(
        key: const Key('print-sheet'),
        title: widget.title,
        subtitle: widget.subtitle,
        children: [
          Card(
            child: Column(
              children: [
                if (counter) ...[
                  option(
                    PrintOn.counter,
                    ready
                        ? settings!.name ?? 'Counter printer'
                        : 'Counter printer',
                    ready
                        ? 'Bluetooth · $paper mm'
                        : 'Choose your Bluetooth printer to use it',
                    key: const Key('print-on-counter'),
                  ),
                  const Divider(height: 1),
                ],
                option(
                  PrintOn.phone,
                  'Other printers or PDF',
                  widget.fullPage
                      ? 'A4 page · Wi-Fi and USB printers, or save as a PDF'
                      : 'Wi-Fi and USB printers, or save as a PDF',
                  key: const Key('print-on-phone'),
                ),
              ],
            ),
          ),
          if (on == PrintOn.counter) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('Copies', style: theme.textTheme.bodyLarge),
                ),
                StepButton(
                  key: const Key('print-fewer'),
                  icon: Icons.remove,
                  tooltip: 'One fewer',
                  onPressed: _copies > 1
                      ? () => setState(() => _copies--)
                      : null,
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '$_copies',
                    key: const Key('print-copies'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                StepButton(
                  key: const Key('print-more'),
                  icon: Icons.add,
                  tooltip: 'One more',
                  onPressed: _copies < 9
                      ? () => setState(() => _copies++)
                      : null,
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('print-go'),
            onPressed: _busy ? null : () => _print(on),
            child: const Text('Print'),
          ),
          if (counter)
            TextButton(
              key: const Key('print-set-up'),
              onPressed: _setUp,
              child: Text(
                ready ? 'Receipt printer settings' : 'Set up a receipt printer',
              ),
            ),
        ],
      ),
    );
  }
}
