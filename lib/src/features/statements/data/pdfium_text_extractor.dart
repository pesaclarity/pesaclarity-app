import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:ujumbe/ujumbe.dart' show StatementPage;

import 'page_words.dart';
import 'pdf_text_extractor.dart';

/// Extracts positioned words with PDFium, through pdfrx_engine.
class PdfiumTextExtractor implements PdfTextExtractor {
  PdfiumTextExtractor({this.tempDirectory});

  /// Where the engine may keep scratch files; the app's cache by default.
  final String? tempDirectory;

  static Future<void>? _initialising;

  // PDFium itself is packaged by the pdfium_flutter dependency's build hooks.
  // pdfrx_engine runs PDFium calls on its own background worker, so the UI
  // isolate only waits.
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
  Future<List<StatementPage>> extractPages(
    Uint8List bytes, {
    String? password,
  }) async {
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
      final pages = <StatementPage>[];
      for (final page in document.pages) {
        final text = await page.loadText();
        pages.add(
          text == null
              ? const StatementPage([])
              : pageFromCharacters(text.fullText, [
                  for (final r in text.charRects)
                    (r.left, r.top, r.right, r.bottom),
                ], pageHeight: page.height),
        );
      }
      return pages;
    } on Object catch (error) {
      throw PdfUnreadable(error);
    } finally {
      await document.dispose();
    }
  }
}
