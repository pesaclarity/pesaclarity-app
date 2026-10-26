import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../theme/brand_tokens.dart';
import '../money/money.dart';
import '../money/money_format.dart';
import 'export_table.dart';

/// Writes [workbook] as a landscape A4 PDF, each table under its own heading
/// and starting on a new page. Long tables run on over as many pages as they
/// need, with the column headings repeated.
///
/// [subtitle] goes under the title, such as the period covered.
Future<Uint8List> encodePdf(
  ExportWorkbook workbook, {
  required DateTime createdAt,
  String? subtitle,
}) {
  final brand = PdfColor.fromInt(BrandTokens.brand.toARGB32());
  final muted = PdfColor.fromInt(BrandTokens.textMuted.toARGB32());
  final border = PdfColor.fromInt(BrandTokens.border.toARGB32());
  final soft = PdfColor.fromInt(BrandTokens.brandSoft.toARGB32());

  final doc = pw.Document(
    title: workbook.title,
    creator: 'Pesa Clarity',
    producer: 'Pesa Clarity',
  );
  for (final (index, table) in workbook.tables.indexed) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Pesa Clarity. Made on this phone, '
              '${nairobiTimestamp(createdAt)}.',
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 8, color: muted),
            ),
          ],
        ),
        build: (context) => [
          if (index == 0) ...[
            pw.Text(
              _latin1(workbook.title),
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: brand,
              ),
            ),
            if (subtitle != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  _latin1(subtitle),
                  style: pw.TextStyle(fontSize: 10, color: muted),
                ),
              ),
            pw.SizedBox(height: 14),
          ],
          if (workbook.tables.length > 1 || table.title != workbook.title)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                _latin1(table.title),
                style: const pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          if (table.rows.isEmpty)
            pw.Text(
              'Nothing to show for this period.',
              style: pw.TextStyle(fontSize: 10, color: muted),
            )
          else
            _table(table, border: border, headerFill: soft),
        ],
      ),
    );
  }
  return doc.save();
}

pw.Widget _table(
  ExportTable table, {
  required PdfColor border,
  required PdfColor headerFill,
}) {
  final numeric = {
    for (var c = 0; c < table.columns.length; c++)
      if (table.rows.any((r) => r[c] is Money || r[c] is int)) c,
  };
  return pw.TableHelper.fromTextArray(
    headers: table.columns.map(_latin1).toList(),
    data: [
      for (final row in table.rows) [for (final cell in row) _text(cell)],
    ],
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(color: border, width: 0.5),
      bottom: pw.BorderSide(color: border, width: 0.5),
    ),
    headerDecoration: pw.BoxDecoration(color: headerFill),
    headerStyle: const pw.TextStyle(
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
    ),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    headerAlignments: {for (final c in numeric) c: pw.Alignment.centerRight},
    cellAlignments: {for (final c in numeric) c: pw.Alignment.centerRight},
    headerAlignment: pw.Alignment.centerLeft,
    cellAlignment: pw.Alignment.centerLeft,
  );
}

String _text(Object? cell) => switch (cell) {
  null => '',
  final String s => _latin1(s),
  final int n => n.toString(),
  final Money m => formatMoney(m, withCurrency: false),
  final DateTime d => nairobiTimestamp(d),
  _ => throw ArgumentError.value(cell, 'cell'),
};

/// The PDF's built-in fonts cover Latin-1 only; anything else becomes `?`
/// rather than failing the export.
String _latin1(String s) => String.fromCharCodes(
  s.runes.map((r) => r == 0x2014 || r == 0x2013 ? 0x2D : (r > 0xFF ? 0x3F : r)),
);
