import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/printing/slip.dart';
import '../data/counter_printer.dart';

/// The counter printer the business prints on, its paper and whether a
/// receipt prints after each sale.
class PrinterSettings {
  const PrinterSettings({
    this.address,
    this.name,
    this.paperMm = 58,
    this.printAfterSale = false,
  });

  factory PrinterSettings.fromJson(Map<String, Object?>? json) {
    if (json == null) return const PrinterSettings();
    final paper = json['paperMm'];
    return PrinterSettings(
      address: json['address'] as String?,
      name: json['name'] as String?,
      paperMm: paper == 80 ? 80 : 58,
      printAfterSale: json['printAfterSale'] == true,
    );
  }

  /// The chosen printer's Bluetooth address; null until one is chosen.
  final String? address;
  final String? name;

  /// 58 or 80.
  final int paperMm;
  final bool printAfterSale;

  bool get hasPrinter => address != null;

  PrinterSettings copyWith({
    String? address,
    String? name,
    int? paperMm,
    bool? printAfterSale,
  }) => PrinterSettings(
    address: address ?? this.address,
    name: name ?? this.name,
    paperMm: paperMm ?? this.paperMm,
    printAfterSale: printAfterSale ?? this.printAfterSale,
  );

  Map<String, Object?> toJson() => {
    'address': address,
    'name': name,
    'paperMm': paperMm,
    'printAfterSale': printAfterSale,
  };
}

/// The open business's counter printer settings.
class PrinterSettingsController extends AsyncNotifier<PrinterSettings> {
  static const settingsKey = 'printing.counter';

  @override
  Future<PrinterSettings> build() async => PrinterSettings.fromJson(
    await ref.watch(appSettingsRepositoryProvider).readJson(settingsKey),
  );

  Future<void> save(PrinterSettings next) async {
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
  }
}

final printerSettingsProvider =
    AsyncNotifierProvider<PrinterSettingsController, PrinterSettings>(
      PrinterSettingsController.new,
    );

/// Whether this phone can use a counter printer at all.
final counterPrintingSupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(counterPrintersProvider).supported(),
);

/// Hands a PDF to the phone's own printing: Wi-Fi and USB printers, or
/// Save as PDF. Tests swap in a stand-in.
typedef PdfPrinter = Future<bool> Function(Uint8List pdf, String name);

final pdfPrinterProvider = Provider<PdfPrinter>(
  (ref) =>
      (pdf, name) => Printing.layoutPdf(onLayout: (_) async => pdf, name: name),
);

/// Sends slips to the counter printer and documents to the phone's
/// printers.
class SlipPrinter {
  SlipPrinter(this._ref);

  final Ref _ref;

  /// Prints [slip] [copies] times on the counter printer. Throws when there
  /// is no printer, no Bluetooth access, or the printer can't be reached.
  Future<void> onCounter(Slip slip, {int copies = 1}) async {
    final settings = await _ref.read(printerSettingsProvider.future);
    final address = settings.address;
    if (address == null) throw StateError('No counter printer chosen');
    final printers = _ref.read(counterPrintersProvider);
    if (!await printers.access(ask: true)) {
      throw StateError('Bluetooth access not given');
    }
    final bytes = slip.escPos(settings.paperMm);
    for (var i = 0; i < copies; i++) {
      await printers.print(address, bytes);
    }
  }

  /// Whether a receipt prints by itself after each sale: the business
  /// asked for it, chose a printer, and the phone can print on one.
  Future<bool> printsAfterSale() async {
    final settings = await _ref.read(printerSettingsProvider.future);
    if (!settings.printAfterSale || !settings.hasPrinter) return false;
    return _ref.read(counterPrintingSupportedProvider.future);
  }

  /// Prints [pdf] on the phone's printers, or saves it as a PDF.
  Future<bool> onPhone(Uint8List pdf, String name) =>
      _ref.read(pdfPrinterProvider)(pdf, name);
}

final slipPrinterProvider = Provider<SlipPrinter>(SlipPrinter.new);

/// [slip] as a narrow PDF, for printing it on any printer.
Future<Uint8List> slipPdf(Slip slip, {int columns = 40}) async {
  final doc = pw.Document();
  final lines = slip.render(columns);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.roll80,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            pw.Text(
              line,
              style: pw.TextStyle(font: pw.Font.courier(), fontSize: 8),
            ),
        ],
      ),
    ),
  );
  return doc.save();
}
