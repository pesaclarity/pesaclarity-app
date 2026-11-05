import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../../../data/repositories/documents_repository.dart';
import '../../backup/application/backup_providers.dart';
import '../../documents/application/document_providers.dart';
import '../../insights/application/report_sharer.dart';
import '../../spaces/application/spaces_providers.dart';
import '../../tax/application/tax_providers.dart';
import 'invoice_pdf.dart';
import 'invoice_providers.dart';

/// Turns an invoice into PDF bytes; tests swap in a stand-in.
final invoiceRendererProvider =
    Provider<
      Future<Uint8List> Function(
        InvoiceDoc doc, {
        bool withInvoice,
        bool withTimesheet,
      })
    >((ref) => renderInvoicePdf);

/// Each page of a PDF as a PNG, so an attached PDF can follow the invoice
/// in one file; tests swap in a stand-in.
final pdfPagesProvider =
    Provider<Future<List<Uint8List>> Function(Uint8List pdf)>(
      (ref) =>
          (pdf) async => [
            await for (final page in Printing.raster(pdf, dpi: 150))
              await page.toPng(),
          ],
    );

/// Builds, shares and saves invoices.
class InvoiceSender {
  InvoiceSender(this._ref);

  final Ref _ref;

  Future<InvoiceDoc> docFor(InvoiceView view) async {
    final settings = await _ref.read(documentSettingsProvider.future);
    final pack = await _ref.read(taxPackProvider.future);
    final tax = await _ref.read(taxSettingsProvider.future);
    final logo = await _ref.read(
      documentFileProvider(DocumentFileKind.logo).future,
    );
    final qr = await _ref.read(
      documentFileProvider(DocumentFileKind.mpesaQr).future,
    );
    return InvoiceDoc(
      invoice: view.invoice,
      business: settings.nameOr(_ref.read(activeSpaceProvider).name),
      settings: settings,
      withholdingRate: pack.withholdingRate,
      vatRate: tax.vatRegistered ? pack.vatRate : null,
      hours: await _ref.read(invoicesControllerProvider).hoursOf(view.invoice),
      logo: logo != null && logo.isImage ? logo.bytes : null,
      qr: qr != null && qr.isImage ? qr.bytes : null,
      paid: view.leftMinor == 0,
      attachedPages: await _pages(view.invoice.id),
    );
  }

  Future<List<StoredFile>> _attachments(int invoiceId) =>
      _ref.read(documentsRepositoryProvider).attachments(invoiceId);

  /// Attachments as page pictures: pictures as they are, PDFs page by page.
  /// A file that will not open is left for the separate files.
  Future<List<Uint8List>> _pages(int invoiceId) async {
    final out = <Uint8List>[];
    for (final f in await _attachments(invoiceId)) {
      try {
        if (f.isImage) {
          out.add(f.bytes);
        } else if (f.mimeType == 'application/pdf') {
          out.addAll(await _ref.read(pdfPagesProvider)(f.bytes));
        }
      } on Object {
        continue;
      }
    }
    return out;
  }

  /// The files to send: one PDF, or the invoice and the timesheet apart.
  Future<List<SharedFile>> files(InvoiceDoc doc, {required bool one}) async {
    final render = _ref.read(invoiceRendererProvider);
    if (one) {
      return [
        (
          bytes: await render(doc),
          fileName: doc.fileName(''),
          mimeType: 'application/pdf',
        ),
      ];
    }
    return [
      (
        bytes: await render(doc.withoutAttachedPages(), withTimesheet: false),
        fileName: doc.fileName(''),
        mimeType: 'application/pdf',
      ),
      if (doc.invoice.timesheet && doc.hours.isNotEmpty)
        (
          bytes: await render(doc, withInvoice: false),
          fileName: doc.fileName('timesheet'),
          mimeType: 'application/pdf',
        ),
      for (final a in await _attachments(doc.invoice.id))
        (bytes: a.bytes, fileName: a.name, mimeType: a.mimeType),
    ];
  }

  Future<void> share(InvoiceDoc doc, {required bool one}) async {
    final out = await files(doc, one: one);
    await _ref
        .read(reportSharerProvider)
        .shareFiles(out, subject: 'Invoice ${doc.invoice.number}');
  }

  /// Saves each file through the phone's own save screen. Returns how many
  /// were saved.
  Future<int> save(InvoiceDoc doc, {required bool one}) async {
    final dir = await getTemporaryDirectory();
    var saved = 0;
    for (final f in await files(doc, one: one)) {
      final file = File(p.join(dir.path, f.fileName));
      await file.writeAsBytes(f.bytes, flush: true);
      if (await _ref
          .read(documentStorageProvider)
          .saveAs(file, f.fileName, mimeType: f.mimeType)) {
        saved++;
      }
    }
    return saved;
  }
}

final invoiceSenderProvider = Provider<InvoiceSender>(InvoiceSender.new);
