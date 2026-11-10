import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/printing/slip.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
import '../application/printing_providers.dart';
import '../data/counter_printer.dart';

/// The printers paired with the phone, read again when the screen opens
/// or Bluetooth access changes.
final pairedPrintersProvider = FutureProvider.autoDispose<List<PairedPrinter>?>(
  (ref) async {
    final printers = ref.watch(counterPrintersProvider);
    if (!await printers.supported()) return const [];
    if (!await printers.access()) return null;
    return printers.paired();
  },
);

/// Receipt printer: the Bluetooth printer at the counter, its paper, and
/// whether a receipt prints after each sale.
class ReceiptPrinterScreen extends ConsumerWidget {
  const ReceiptPrinterScreen({super.key});

  static const testSlip = Slip([
    SlipCentre('Pesa Clarity', bold: true, large: true),
    SlipCentre('Test print'),
    SlipRule(),
    SlipPair('Receipt', 'TEST-0001'),
    SlipPair('Item', '100'),
    SlipRule(),
    SlipPair('TOTAL', '100', bold: true),
    SlipRule(),
    SlipCentre('Your printer is ready.'),
  ]);

  Future<void> _test(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(slipPrinterProvider).onCounter(testSlip);
      if (context.mounted) showNote(context, 'Test printed.');
    } on Object {
      if (context.mounted) {
        showNote(
          context,
          'Turn the printer on and keep it close to the phone, then try '
          'again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final supported =
        ref.watch(counterPrintingSupportedProvider).value ?? false;
    final settings = ref.watch(printerSettingsProvider).value;
    final paired = ref.watch(pairedPrintersProvider);
    final controller = ref.read(printerSettingsProvider.notifier);
    final printers = ref.read(counterPrintersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt printer')),
      body: settings == null
          ? const LoadingView()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                Text(
                  supported
                      ? "Print receipts and the day's summary on a small "
                            'Bluetooth printer at your counter. Pair it in '
                            "your phone's Bluetooth settings, then choose it "
                            'here.'
                      : 'Counter printers work with Pesa Clarity on '
                            'Android. On this phone, print on any AirPrint '
                            'printer or save a PDF from the Print button.',
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: colors.textMuted,
                  ),
                ),
                if (supported) ...[
                  const SectionLabel('Paired printers'),
                  switch (paired) {
                    AsyncData(value: null) => Card(
                      child: ListTile(
                        key: const Key('printer-allow'),
                        title: const Text('Allow Nearby devices'),
                        subtitle: const Text(
                          'So Pesa Clarity can see the printers paired with '
                          'this phone',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          await printers.access(ask: true);
                          ref.invalidate(pairedPrintersProvider);
                        },
                      ),
                    ),
                    AsyncData(:final value?) when value.isEmpty => Card(
                      child: ListTile(
                        title: const Text('Pair your printer first'),
                        subtitle: const Text(
                          'Turn it on, pair it in Bluetooth settings, then '
                          'come back here',
                        ),
                        trailing: const Icon(Icons.refresh),
                        onTap: () => ref.invalidate(pairedPrintersProvider),
                      ),
                    ),
                    AsyncData(:final value?) => Card(
                      child: RadioGroup<String>(
                        groupValue: settings.address,
                        onChanged: (address) {
                          final chosen = value
                              .where((p) => p.address == address)
                              .firstOrNull;
                          if (chosen == null) return;
                          controller.save(
                            settings.copyWith(
                              address: chosen.address,
                              name: chosen.name,
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            for (final (i, p) in value.indexed) ...[
                              if (i > 0) const Divider(height: 1),
                              RadioListTile<String>(
                                key: Key('printer-${p.address}'),
                                value: p.address,
                                title: Text(p.name),
                                subtitle: Text(
                                  p.address == settings.address
                                      ? 'Prints your receipts'
                                      : 'Paired with this phone',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    AsyncError() => ErrorView(
                      'Paired printers could not load.',
                      onRetry: () => ref.invalidate(pairedPrintersProvider),
                    ),
                    _ => const LoadingView(inList: true),
                  },
                  const SectionLabel('Paper width'),
                  AdaptiveSegmented<int>(
                    key: const Key('printer-paper'),
                    segments: const [(58, '58 mm'), (80, '80 mm')],
                    selected: settings.paperMm,
                    onChanged: (mm) =>
                        controller.save(settings.copyWith(paperMm: mm)),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: SwitchListTile.adaptive(
                      key: const Key('printer-after-sale'),
                      title: const Text('Print after each sale'),
                      subtitle: const Text(
                        'A receipt prints when you tap Done',
                      ),
                      value: settings.printAfterSale,
                      onChanged: settings.hasPrinter
                          ? (on) => controller.save(
                              settings.copyWith(printAfterSale: on),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    key: const Key('printer-test'),
                    onPressed: settings.hasPrinter
                        ? () => _test(context, ref)
                        : null,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print a test'),
                  ),
                  TextButton(
                    key: const Key('printer-bluetooth'),
                    onPressed: () async {
                      await printers.openSettings();
                      ref.invalidate(pairedPrintersProvider);
                    },
                    child: const Text('Open Bluetooth settings'),
                  ),
                ],
              ],
            ),
    );
  }
}
