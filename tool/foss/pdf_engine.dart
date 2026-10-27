// Copied over lib/src/features/statements/data/pdf_engine.dart by
// tool/prepare_foss.sh. F-Droid accepts no prebuilt PDFium, so this build
// has no PDF engine and hides statement import.
import 'pdf_text_extractor.dart';

/// The PDF engine this build ships with: none.
PdfTextExtractor? createPdfTextExtractor() => null;
