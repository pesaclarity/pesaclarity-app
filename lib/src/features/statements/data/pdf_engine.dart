// The F-Droid build replaces this file with tool/foss/pdf_engine.dart, which
// has no PDFium. Keep the two in step.
import 'pdf_text_extractor.dart';
import 'pdfium_text_extractor.dart';

/// The PDF engine this build ships with.
PdfTextExtractor? createPdfTextExtractor() => PdfiumTextExtractor();
