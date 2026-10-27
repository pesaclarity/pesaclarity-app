import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pdf_engine.dart';

/// The PDF is encrypted and needs a password to open.
class PdfPasswordRequired implements Exception {
  const PdfPasswordRequired();
}

/// The password given did not open the PDF.
class PdfWrongPassword implements Exception {
  const PdfWrongPassword();
}

/// The file is not a PDF the extractor can open.
class PdfUnreadable implements Exception {
  const PdfUnreadable(this.cause);

  final Object cause;

  @override
  String toString() => 'PdfUnreadable($cause)';
}

/// Pulls the text out of a PDF, on the phone.
abstract interface class PdfTextExtractor {
  /// The text of every page of [bytes], in order, separated by form feeds.
  ///
  /// [password] opens an encrypted PDF. It is passed straight to the PDF
  /// engine and not kept. Throws [PdfPasswordRequired], [PdfWrongPassword]
  /// or [PdfUnreadable].
  Future<String> extractText(Uint8List bytes, {String? password});
}

/// The PDF engine of this build, or null when it has none: the F-Droid
/// build leaves PDFium out (see `tool/prepare_foss.sh`).
final pdfTextExtractorProvider = Provider<PdfTextExtractor?>(
  (ref) => createPdfTextExtractor(),
);

/// Whether this build can import statement PDFs.
final statementImportAvailableProvider = Provider<bool>(
  (ref) => ref.watch(pdfTextExtractorProvider) != null,
);
