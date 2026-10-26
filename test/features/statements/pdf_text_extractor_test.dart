import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx_engine/pdfrx_engine.dart';
import 'package:pesaclarity/src/features/statements/data/pdf_text_extractor.dart';
import 'package:ujumbe/ujumbe.dart';

/// The PDFium library the build hook fetched for this host, which
/// `flutter test` does not load on its own.
String? _hostPdfium() {
  final build = Directory('.dart_tool/hooks_runner/shared/pdfium_dart/build');
  if (!build.existsSync()) return null;
  for (final entity in build.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('/libpdfium.so')) {
      return entity.absolute.path;
    }
  }
  return null;
}

// The fixtures are synthetic two-page statements made for this test, one
// encrypted with the password 0000.
void main() {
  final pdfium = _hostPdfium();
  if (pdfium == null) {
    test('PDFium is not built for this host', () {}, skip: true);
    return;
  }

  late PdfiumTextExtractor extractor;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('pdfrx');
    addTearDown(() => dir.delete(recursive: true));
    Pdfrx.pdfiumModulePath = pdfium;
    extractor = PdfiumTextExtractor(tempDirectory: dir.path);
  });

  final plain = File('test/fixtures/synthetic_statement.pdf').readAsBytesSync();
  final locked = File('test/fixtures/synthetic_statement_locked.pdf')
      .readAsBytesSync();

  test('extracts every page, ready for the statement parser', () async {
    final text = await extractor.extractText(plain);

    expect(text, contains('\f'));
    final statement = const MpesaStatementParser().parse(text);
    expect(statement.transactions, hasLength(3));
    expect(statement.closingBalanceMinor, 513500);
    expect(statement.reconciles, isTrue);
  });

  test(
    'asks for a password, rejects a wrong one, opens with the right one',
    () async {
      await expectLater(
        extractor.extractText(locked),
        throwsA(isA<PdfPasswordRequired>()),
      );
      await expectLater(
        extractor.extractText(locked, password: '1111'),
        throwsA(isA<PdfWrongPassword>()),
      );
      final text = await extractor.extractText(locked, password: '0000');
      expect(
        const MpesaStatementParser().parse(text).transactions,
        hasLength(3),
      );
    },
  );

  test('a file that is not a PDF is unreadable', () async {
    await expectLater(
      extractor.extractText(plain.sublist(0, 20)),
      throwsA(isA<PdfUnreadable>()),
    );
  });
}
