import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../theme/brand_tokens.dart';
import 'report_content.dart';

/// Turns a business report into PDF bytes; widget tests swap in a stand-in.
final businessReportRendererProvider =
    Provider<Future<Uint8List> Function(ReportDocument)>(
      (ref) => renderBusinessReport,
    );

/// [doc] as an A4 PDF in the app's report style: the business on top, then
/// each part as a table, with the page number at the foot of each page.
Future<Uint8List> renderBusinessReport(ReportDocument doc) {
  final brand = PdfColor.fromInt(BrandTokens.brand.toARGB32());
  final text = PdfColor.fromInt(BrandTokens.text.toARGB32());
  final muted = PdfColor.fromInt(BrandTokens.textMuted.toARGB32());
  final border = PdfColor.fromInt(BrandTokens.border.toARGB32());
  final soft = PdfColor.fromInt(BrandTokens.brandSoft.toARGB32());

  String money(int minor) {
    final plain = formatMoney(Money(minor.abs()), withCurrency: false);
    return minor < 0 ? '- $plain' : plain;
  }

  String cell(Object? value) => switch (value) {
    null => '',
    final int minor => money(minor),
    final CalendarDate d => dayLabel(d, thisYear: doc.period.lastDay.year),
    _ => _latin1('$value'),
  };

  pw.Widget heading(String label) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 18, bottom: 6),
    child: pw.Text(
      _latin1(label),
      style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
    ),
  );

  List<pw.Widget> table(ReportTable t) {
    final count = t.columns.length;
    final numeric = [
      for (var i = 0; i < count; i++)
        i > 0 &&
            [...t.rows, ?t.total].any(
              (r) => i < r.length && (r[i] is int || '${r[i]}'.endsWith('%')),
            ),
    ];
    pw.Widget text0(
      Object? value,
      int i, {
      bool bold = false,
      bool header = false,
    }) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        header ? _latin1('${value ?? ''}') : cell(value),
        textAlign: numeric[i] ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: header ? 8 : 10,
          color: header ? muted : text,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );

    List<Object?> padded(List<Object?> r) => [
      for (var i = 0; i < count; i++) i < r.length ? r[i] : null,
    ];
    final hasHeader = t.columns.any((c) => c.isNotEmpty);
    return [
      pw.Table(
        columnWidths: {
          for (var i = 0; i < count; i++)
            i: i == (count > 3 ? 1 : 0)
                ? const pw.FlexColumnWidth(3)
                : const pw.FlexColumnWidth(),
        },
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: border, width: 0.5),
        ),
        children: [
          if (hasHeader)
            pw.TableRow(
              decoration: pw.BoxDecoration(color: soft),
              children: [
                for (final (i, c) in t.columns.indexed)
                  text0(c, i, header: true),
              ],
            ),
          for (final r in t.rows)
            pw.TableRow(
              children: [for (final (i, c) in padded(r).indexed) text0(c, i)],
            ),
          if (t.rows.isEmpty)
            pw.TableRow(
              children: [
                text0('Nothing in this period.', 0),
                for (var i = 1; i < count; i++) text0(null, i),
              ],
            ),
          if (t.total case final total?)
            pw.TableRow(
              decoration: pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: text)),
              ),
              children: [
                for (final (i, c) in padded(total).indexed)
                  text0(c, i, bold: true),
              ],
            ),
        ],
      ),
      if (t.note case final note?)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text(
            _latin1(note),
            style: pw.TextStyle(fontSize: 8, color: muted),
          ),
        ),
    ];
  }

  pw.Widget notes(ReportNotes n) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final l in n.lines)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 4,
                height: 4,
                margin: const pw.EdgeInsets.only(top: 4, right: 8),
                decoration: pw.BoxDecoration(
                  color: brand,
                  shape: pw.BoxShape.circle,
                ),
              ),
              pw.Expanded(child: pw.Text(_latin1(l))),
            ],
          ),
        ),
    ],
  );

  final details = doc.coverLine.startsWith(doc.business)
      ? doc.coverLine
            .substring(doc.business.length)
            .replaceFirst(RegExp(r'^\s*·\s*'), '')
      : doc.coverLine;
  final theme = pw.ThemeData.base();
  final made = periodText(ReportPeriod(doc.made, doc.made.addDays(1), ''));
  final pdf = pw.Document(
    title: _latin1(doc.title),
    author: _latin1(doc.business),
    creator: 'Pesa Clarity',
    producer: 'Pesa Clarity',
  );
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 0, 36, 28),
      theme: theme.copyWith(
        defaultTextStyle: theme.defaultTextStyle.copyWith(
          color: text,
          fontSize: 10,
        ),
      ),
      header: (context) => pw.Column(
        children: [
          pw.Container(height: 4, color: brand),
          pw.SizedBox(height: context.pageNumber == 1 ? 28 : 16),
        ],
      ),
      footer: (context) => pw.Column(
        children: [
          pw.Divider(color: border),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Made on this phone by Pesa Clarity on $made, from '
                  "the business's own records.",
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: muted),
              ),
            ],
          ),
        ],
      ),
      build: (context) => [
        pw.Row(
          children: [
            if (doc.logo case final logo?) ...[
              pw.Image(pw.MemoryImage(logo), height: 32),
              pw.SizedBox(width: 10),
            ],
            pw.Expanded(
              child: pw.Text(
                _latin1(doc.business),
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: brand,
                ),
              ),
            ),
          ],
        ),
        if (details.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(_latin1(details), style: pw.TextStyle(color: muted)),
        ],
        pw.SizedBox(height: 10),
        pw.Text(
          _latin1(doc.title),
          style: const pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          '${_latin1(doc.periodLine)}. Amounts in ${doc.currency}.',
          style: pw.TextStyle(color: muted),
        ),
        for (final block in doc.blocks)
          // A short part stays on one page with its heading; a long one,
          // such as the cash book, runs on over pages.
          if (block is ReportTable &&
              block.rows.length > _rowsKeptTogether) ...[
            heading(block.title),
            ...table(block),
          ] else
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                heading(block.title),
                ...switch (block) {
                  ReportTable() => table(block),
                  ReportNotes() => [notes(block)],
                },
              ],
            ),
      ],
    ),
  );
  return pdf.save();
}

/// Parts with more rows than this may run on over pages.
const _rowsKeptTogether = 30;

/// The built-in PDF fonts cover Latin-1 only.
String _latin1(String s) => String.fromCharCodes(
  s
      .replaceAll('−', '-')
      .replaceAll(RegExp('[‘’]'), "'")
      .replaceAll(RegExp('[“”]'), '"')
      .replaceAll(RegExp('[–—]'), '-')
      .runes
      .map((r) => r > 0xFF ? 0x3F : r),
);
