import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/books/report_setup.dart';
import '../../../domain/documents/document_settings.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';
import '../../../theme/brand_tokens.dart';
import 'report_content.dart';

/// Turns a business report into PDF bytes; widget tests swap in a stand-in.
final businessReportRendererProvider =
    Provider<Future<Uint8List> Function(ReportDocument)>(
      (ref) => renderBusinessReport,
    );

/// The grey a formal report uses in place of the brand's red tint.
const _formalSoft = PdfColor.fromInt(0xFFEFEFEF);

/// [doc] as an A4 PDF in the style it asks for: the business on top, then
/// each part as a table or chart, with the page number at the foot of each
/// page.
Future<Uint8List> renderBusinessReport(ReportDocument doc) {
  final style = doc.style;
  final formal = style.colour == ReportColour.formal;
  final text = PdfColor.fromInt(BrandTokens.text.toARGB32());
  final brand = formal
      ? PdfColors.grey900
      : PdfColor.fromInt(BrandTokens.brand.toARGB32());
  final muted = PdfColor.fromInt(BrandTokens.textMuted.toARGB32());
  final border = PdfColor.fromInt(BrandTokens.border.toARGB32());
  final soft = formal
      ? _formalSoft
      : PdfColor.fromInt(BrandTokens.brandSoft.toARGB32());

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

  pw.Widget chart(ReportChart c) {
    if (c.points.isEmpty) {
      return pw.Text(
        'Nothing in this period.',
        style: pw.TextStyle(color: muted),
      );
    }
    final top = c.points.fold(
      1,
      (m, p) => p.valueMinor.abs() > m ? p.valueMinor.abs() : m,
    );
    if (!c.columns) {
      return pw.Column(
        children: [
          for (final p in c.points)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 90,
                    child: pw.Text(
                      _latin1(p.label),
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.LayoutBuilder(
                      builder: (context, constraints) => pw.Row(
                        children: [
                          pw.Container(
                            width:
                                (constraints?.maxWidth ?? 300) *
                                0.85 *
                                p.valueMinor.abs() /
                                top,
                            height: 8,
                            color: brand,
                          ),
                        ],
                      ),
                    ),
                  ),
                  pw.SizedBox(
                    width: 70,
                    child: pw.Text(
                      money(p.valueMinor),
                      textAlign: pw.TextAlign.right,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    const height = 80.0;
    final negative = c.points.any((p) => p.valueMinor < 0);
    // With a loss in the chart, gains grow up and losses down from the middle.
    final up = negative ? height / 2 : height;
    final down = height - up;
    final every = (c.points.length / 12).ceil().clamp(1, c.points.length);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final p in c.points)
              pw.Expanded(
                child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 1),
                  child: pw.Column(
                    children: [
                      pw.SizedBox(
                        height: up * (1 - p.valueMinor.clamp(0, top) / top),
                      ),
                      pw.Container(
                        height: up * p.valueMinor.clamp(0, top) / top,
                        color: brand,
                      ),
                      pw.Container(
                        height: down * (-p.valueMinor).clamp(0, top) / top,
                        color: muted,
                      ),
                      pw.SizedBox(
                        height:
                            down * (1 - (-p.valueMinor).clamp(0, top) / top),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        pw.Container(height: 0.5, color: border),
        pw.SizedBox(height: 2),
        pw.Row(
          children: [
            for (final (i, p) in c.points.indexed)
              pw.Expanded(
                child: pw.Text(
                  i % every == 0 ? _latin1(p.label) : '',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 7, color: muted),
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Highest ${money(top)}${negative ? '; grey is a loss' : ''}.',
          style: pw.TextStyle(fontSize: 8, color: muted),
        ),
      ],
    );
  }

  pw.Widget signature() => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 36),
    child: pw.Row(
      children: [
        for (final label in ['Signed', 'Name', 'Date']) ...[
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.SizedBox(height: 24),
                pw.Container(height: 0.6, color: text),
                pw.SizedBox(height: 3),
                pw.Text(label, style: pw.TextStyle(fontSize: 8, color: muted)),
              ],
            ),
          ),
          if (label != 'Date') pw.SizedBox(width: 18),
        ],
      ],
    ),
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
  final band = style.cover == ReportCoverStyle.band;
  const bandHeight = 92.0;
  pw.Widget mark({required bool onBand}) => doc.logo != null
      ? pw.Image(pw.MemoryImage(doc.logo!), height: 32)
      : onBand
      ? pw.Container(
          width: 32,
          height: 32,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(
            _latin1(DocumentSettings.initials(doc.business)),
            style: pw.TextStyle(
              color: brand,
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        )
      : pw.SizedBox();
  pw.Widget bandHeader() => pw.Container(
    height: bandHeight,
    padding: const pw.EdgeInsets.only(bottom: 14),
    alignment: pw.Alignment.bottomLeft,
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        mark(onBand: true),
        pw.SizedBox(width: 10),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                _latin1(doc.business),
                style: const pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
              ),
              if (details.isNotEmpty)
                pw.Text(
                  _latin1(details),
                  style: const pw.TextStyle(color: PdfColors.white),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  pdf.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 0, 36, 28),
        theme: theme.copyWith(
          defaultTextStyle: theme.defaultTextStyle.copyWith(
            color: text,
            fontSize: 10,
          ),
        ),
        // The full band runs edge to edge across the top of the first page.
        buildBackground: band
            ? (context) => context.pageNumber == 1
                  ? pw.FullPage(
                      ignoreMargins: true,
                      child: pw.Column(
                        children: [
                          pw.Container(height: bandHeight, color: brand),
                        ],
                      ),
                    )
                  : pw.SizedBox()
            : null,
      ),
      header: (context) => band && context.pageNumber == 1
          ? pw.Column(children: [bandHeader(), pw.SizedBox(height: 18)])
          : pw.Column(
              children: [
                if (style.cover != ReportCoverStyle.plain)
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
                  reportFooter(style, made),
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
        if (!band) ...[
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
                    color: style.cover == ReportCoverStyle.plain ? text : brand,
                  ),
                ),
              ),
            ],
          ),
          if (details.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(_latin1(details), style: pw.TextStyle(color: muted)),
          ],
        ],
        for (final n in doc.coverNotes)
          pw.Text(_latin1(n), style: pw.TextStyle(color: muted)),
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
          ] else if (block is ReportChart)
            // A chart never splits: it moves whole to the next page.
            pw.Inseparable(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [heading(block.title), chart(block)],
              ),
            )
          else
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                heading(block.title),
                ...switch (block) {
                  ReportTable() => table(block),
                  ReportNotes() => [notes(block)],
                  ReportChart() => [chart(block)],
                },
              ],
            ),
        if (style.signature) signature(),
      ],
    ),
  );
  return pdf.save();
}

/// The line at the foot of each page, naming the app only when [style]
/// keeps its branding.
String reportFooter(ReportStyle style, String made) => style.branding
    ? "Made on this phone by Pesa Clarity on $made, from the business's own "
          'records.'
    : "Made on $made from the business's own records.";

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
