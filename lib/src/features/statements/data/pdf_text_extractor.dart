import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';

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

/// Extracts text with PDFium, through pdfrx_engine.
class PdfiumTextExtractor implements PdfTextExtractor {
  PdfiumTextExtractor({this.tempDirectory});

  /// Where the engine may keep scratch files; the app's cache by default.
  final String? tempDirectory;

  static Future<void>? _initialising;

  // PDFium itself is packaged by the pdfium_flutter dependency's build hooks.
  Future<void> _initialise() => _initialising ??= () async {
    try {
      await pdfrxInitialize(
        tmpPath: tempDirectory ?? (await getTemporaryDirectory()).path,
      );
    } on Object {
      _initialising = null;
      rethrow;
    }
  }();

  @override
  Future<String> extractText(Uint8List bytes, {String? password}) async {
    await _initialise();
    var asked = false;
    final PdfDocument document;
    try {
      document = await PdfDocument.openData(
        bytes,
        sourceName: 'statement',
        passwordProvider: () {
          if (asked) return null;
          asked = true;
          return password;
        },
      );
    } on PdfPasswordException {
      throw password == null
          ? const PdfPasswordRequired()
          : const PdfWrongPassword();
    } on Object catch (error) {
      throw PdfUnreadable(error);
    }
    try {
      final pages = <String>[];
      for (final page in document.pages) {
        pages.add((await page.loadText())?.fullText ?? '');
      }
      return pages.join('\f');
    } on Object catch (error) {
      throw PdfUnreadable(error);
    } finally {
      await document.dispose();
    }
  }
}

final pdfTextExtractorProvider = Provider<PdfTextExtractor>(
  (ref) => PdfiumTextExtractor(),
);
