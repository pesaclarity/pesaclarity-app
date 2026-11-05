import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/documents/receipt.dart';
import '../../../domain/enums.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../shared/format/date_labels.dart' show formatTime;
import '../../../theme/brand_tokens.dart';

/// The receipt's date and time as it prints: `5 Nov 2026 · 14:41`.
String receiptWhen(DateTime at) =>
    '${dateLabel(CalendarDate.local(at))} · ${formatTime(at)}';

/// [r] as a narrow PDF, the width of a till roll, in the app's report
/// style. [logo] is a picture to print on top, else the initials show.
Future<Uint8List> renderReceiptPdf(
  Receipt r, {
  required String Function(SalePaymentMethod) label,
  required String initials,
  Uint8List? logo,
}) {
  // Black and white prints cleanly on a thermal till printer.
  final mono = r.blackAndWhite;
  final brand = mono
      ? PdfColors.black
      : PdfColor.fromInt(BrandTokens.brand.toARGB32());
  final text = mono
      ? PdfColors.black
      : PdfColor.fromInt(BrandTokens.text.toARGB32());
  final muted = mono
      ? PdfColors.black
      : PdfColor.fromInt(BrandTokens.textMuted.toARGB32());
  final border = mono
      ? PdfColors.black
      : PdfColor.fromInt(BrandTokens.border.toARGB32());
  final success = mono
      ? PdfColors.black
      : PdfColor.fromInt(BrandTokens.success.toARGB32());
  String plain(int minor) => formatMoney(Money(minor), withCurrency: false);
  final theme = pw.ThemeData.base();

  pw.Widget dashed() => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 6),
    child: pw.Container(
      height: 0.6,
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: border, style: pw.BorderStyle.dashed),
        ),
      ),
    ),
  );

  final doc = pw.Document(
    title: _latin1('Receipt ${r.number}'),
    author: _latin1(r.business),
    creator: 'Pesa Clarity',
    producer: 'Pesa Clarity',
  );
  doc.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(
        80 * PdfPageFormat.mm,
        double.infinity,
        marginAll: 5 * PdfPageFormat.mm,
      ),
      theme: theme.copyWith(
        defaultTextStyle: theme.defaultTextStyle.copyWith(
          color: text,
          fontSize: 8,
        ),
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(height: 2, color: brand),
          pw.SizedBox(height: 8),
          pw.Center(
            child: logo != null
                ? pw.Image(pw.MemoryImage(logo), height: 28)
                : pw.Container(
                    width: 26,
                    height: 26,
                    alignment: pw.Alignment.center,
                    decoration: pw.BoxDecoration(
                      color: brand,
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Text(
                      _latin1(initials),
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            _latin1(r.business),
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if ([?r.place, ?r.phone].isNotEmpty)
            pw.Text(
              _latin1([?r.place, ?r.phone].join(' · ')),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(color: muted),
            ),
          pw.Text(
            _latin1('Receipt ${r.number} · ${receiptWhen(r.at)}'),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(color: muted),
          ),
          if (r.kraPin case final pin?)
            pw.Text(
              _latin1('KRA PIN $pin'),
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(color: muted),
            ),
          dashed(),
          for (final l in r.lines)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
              child: pw.Row(
                children: [
                  pw.Expanded(child: pw.Text(_latin1(l.label(plain)))),
                  pw.Text(
                    plain(l.totalMinor),
                    style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
          dashed(),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Total',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Text(
                '${r.currency} ${plain(r.totalMinor)}',
                style: const pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: pw.BoxDecoration(
              color: mono
                  ? null
                  : PdfColor(success.red, success.green, success.blue, 0.12),
              border: mono ? pw.Border.all(width: 0.6) : null,
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Text(
              _latin1(receiptPaidLine(r, label, plain)),
              style: pw.TextStyle(color: success, fontSize: 7),
            ),
          ),
          if (r.payTo case final till?) ...[
            pw.SizedBox(height: 4),
            pw.Text(_latin1('Pay to $till'), textAlign: pw.TextAlign.center),
          ],
          if (r.footer case final f? when f.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(_latin1(f), textAlign: pw.TextAlign.center),
          ],
          pw.SizedBox(height: 6),
          pw.Text(
            'This is not an eTIMS tax invoice.',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(color: muted, fontSize: 6.5),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

/// The built-in PDF fonts cover Latin-1 only.
String _latin1(String s) => String.fromCharCodes(
  s
      .replaceAll('−', '-')
      .replaceAll('×', 'x')
      .replaceAll(RegExp('[‘’]'), "'")
      .replaceAll(RegExp('[–—]'), '-')
      .runes
      .map((r) => r > 0xFF ? 0x3F : r),
);
