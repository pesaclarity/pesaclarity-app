import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/documents_repository.dart';
import '../../../domain/documents/document_settings.dart';
import '../../../domain/documents/receipt.dart';
import '../../../domain/people/reminder_text.dart';
import '../../insights/application/report_sharer.dart';
import '../../lending/data/reminder_sharer.dart';
import '../../reminders/application/business_reminders.dart';
import '../../sales/presentation/pay_sheet.dart';
import '../../spaces/application/spaces_providers.dart';
import 'receipt_pdf.dart';

/// The open business's receipt and invoice settings.
class DocumentSettingsController extends AsyncNotifier<DocumentSettings> {
  static const settingsKey = 'documents.settings';

  @override
  Future<DocumentSettings> build() async => DocumentSettings.fromJson(
    await ref.watch(appSettingsRepositoryProvider).readJson(settingsKey),
  );

  Future<void> save(DocumentSettings next) async {
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
  }
}

final documentSettingsProvider =
    AsyncNotifierProvider<DocumentSettingsController, DocumentSettings>(
      DocumentSettingsController.new,
    );

/// The newest file of a kind, such as the logo.
final documentFileProvider = FutureProvider.family<StoredFile?, String>(
  (ref, kind) => ref.watch(documentsRepositoryProvider).file(kind),
);

/// A picture or document picked from the phone.
class PickedDocument {
  const PickedDocument({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

/// The phone's own file picker; it needs no permission.
abstract interface class DocumentPicker {
  /// A picture, such as a logo or an M-PESA QR code; null if backed out.
  Future<PickedDocument?> pickImage();

  /// PDFs or pictures, in the order picked; empty if backed out.
  Future<List<PickedDocument>> pickDocuments();

  /// A photo from the phone's camera, such as a paper receipt; null if
  /// backed out.
  Future<PickedDocument?> takePhoto();
}

class SystemDocumentPicker implements DocumentPicker {
  static const _channel = MethodChannel('com.pesaclarity.app/share');

  static const _images = XTypeGroup(
    label: 'Pictures',
    extensions: ['png', 'jpg', 'jpeg'],
    mimeTypes: ['image/png', 'image/jpeg'],
    uniformTypeIdentifiers: ['public.png', 'public.jpeg'],
  );
  static const _pdf = XTypeGroup(
    label: 'PDF',
    extensions: ['pdf'],
    mimeTypes: ['application/pdf'],
    uniformTypeIdentifiers: ['com.adobe.pdf'],
  );

  static String _mime(XFile f) {
    final known = f.mimeType;
    if (known != null && known.isNotEmpty) return known;
    final name = f.name.toLowerCase();
    if (name.endsWith('.pdf')) return 'application/pdf';
    if (name.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  @override
  Future<PickedDocument?> pickImage() async {
    final f = await openFile(acceptedTypeGroups: const [_images]);
    if (f == null) return null;
    return PickedDocument(
      name: f.name,
      mimeType: _mime(f),
      bytes: await f.readAsBytes(),
    );
  }

  @override
  Future<PickedDocument?> takePhoto() async {
    final path = await _channel.invokeMethod<String>('takePhoto');
    if (path == null) return null;
    final file = File(path);
    try {
      final bytes = await file.readAsBytes();
      final name =
          'Receipt photo ${DateTime.now().toIso8601String().substring(0, 10)}.jpg';
      return PickedDocument(name: name, mimeType: 'image/jpeg', bytes: bytes);
    } finally {
      // The photo is kept in the database from here; the copy goes.
      if (file.existsSync()) await file.delete();
    }
  }

  @override
  Future<List<PickedDocument>> pickDocuments() async => [
    for (final f in await openFiles(acceptedTypeGroups: const [_pdf, _images]))
      PickedDocument(
        name: f.name,
        mimeType: _mime(f),
        bytes: await f.readAsBytes(),
      ),
  ];
}

final documentPickerProvider = Provider<DocumentPicker>(
  (ref) => SystemDocumentPicker(),
);

/// Turns a PDF's first page into a PNG; tests swap in a stand-in, since
/// rasterising needs the phone.
final pdfPictureProvider = Provider<Future<Uint8List> Function(Uint8List pdf)>(
  (ref) => (pdf) async {
    await for (final page in Printing.raster(pdf, pages: [0], dpi: 220)) {
      return page.toPng();
    }
    throw StateError('The receipt has no page');
  },
);

/// Turns a receipt into PDF bytes; tests swap in a stand-in.
final receiptRendererProvider =
    Provider<
      Future<Uint8List> Function(
        Receipt r, {
        required String initials,
        Uint8List? logo,
      })
    >(
      (ref) =>
          (r, {required initials, logo}) => renderReceiptPdf(
            r,
            label: methodLabel,
            initials: initials,
            logo: logo,
          ),
    );

String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

/// Makes receipts for sales and hands them to the share sheet or a
/// messaging app.
class ReceiptMaker {
  ReceiptMaker(this._ref);

  final Ref _ref;

  /// The receipt for sale [saleId], giving it the next number the first
  /// time; null if the sale is gone.
  Future<Receipt?> receiptFor(int saleId) async {
    final repo = _ref.read(documentsRepositoryProvider);
    final sale = await repo.sale(saleId);
    if (sale == null) return null;
    final settings = await _ref.read(documentSettingsProvider.future);
    final space = _ref.read(activeSpaceProvider).name;
    var number = sale.receiptNo;
    if (number == null) {
      number = settings.numberLabel(space, settings.nextReceipt);
      await repo.setReceiptNo(saleId, number);
      await _ref
          .read(documentSettingsProvider.notifier)
          .save(settings.copyWith(nextReceipt: settings.nextReceipt + 1));
    }
    final reminders = await _ref.read(reminderSetupProvider.future);
    return Receipt(
      number: number,
      at: sale.soldAt,
      business: settings.nameOr(space),
      place: settings.place,
      phone: settings.phone,
      payTo: settings.till ?? reminders.till,
      kraPin: settings.showKraPin ? settings.kraPin : null,
      lines: sale.lines,
      totalMinor: sale.totalMinor,
      payments: sale.payments,
      currency: sale.currency,
      footer: settings.footer,
      customer: sale.customer,
    );
  }

  Future<Uint8List> pdf(Receipt r) async {
    final logo = await _ref.read(
      documentFileProvider(DocumentFileKind.logo).future,
    );
    final render = _ref.read(receiptRendererProvider);
    final initials = DocumentSettings.initials(r.business);
    if (logo == null || !logo.isImage) return render(r, initials: initials);
    try {
      return await render(r, initials: initials, logo: logo.bytes);
    } on Object {
      // A logo that will not open leaves the initials on the receipt.
      return render(r, initials: initials);
    }
  }

  String text(Receipt r) => receiptText(
    r,
    label: methodLabel,
    plain: _plain,
    when: receiptWhen(r.at),
  );

  /// Sends [r] as [format]. Text goes to [number] in [app] when there is
  /// one; files and text without a number go to the share sheet. Returns
  /// false when sharing is not there, after copying the text.
  Future<bool> send(
    Receipt r, {
    required ReceiptFormat format,
    String? number,
    SendWith app = SendWith.whatsapp,
  }) async {
    switch (format) {
      case ReceiptFormat.text:
        final message = text(r);
        if (number != null &&
            await _ref
                .read(messageLauncherProvider)
                .open(app, number, message)) {
          return true;
        }
        try {
          await _ref.read(reminderSharerProvider).share(message);
          return true;
        } on PlatformException {
          await Clipboard.setData(ClipboardData(text: message));
          return false;
        }
      case ReceiptFormat.pdf:
        await _ref
            .read(reportSharerProvider)
            .sharePdf(
              await pdf(r),
              fileName: r.fileName('pdf'),
              subject: 'Receipt ${r.number}',
            );
        return true;
      case ReceiptFormat.picture:
        final png = await _ref.read(pdfPictureProvider)(await pdf(r));
        await _ref
            .read(reportSharerProvider)
            .shareFile(
              png,
              fileName: r.fileName('png'),
              mimeType: 'image/png',
              subject: 'Receipt ${r.number}',
            );
        return true;
    }
  }
}

final receiptMakerProvider = Provider<ReceiptMaker>(ReceiptMaker.new);
