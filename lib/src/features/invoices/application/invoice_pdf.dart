import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/invoices_repository.dart';
import '../../../domain/books/business_report.dart'
    show ReportPeriod, periodText;
import '../../../domain/documents/document_settings.dart';
import '../../../domain/documents/invoice.dart';
import '../../../domain/hours/hours.dart';
import '../../../domain/tax/tax_pack.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';
import '../../../theme/brand_tokens.dart';

/// Everything an invoice's PDF shows.
class InvoiceDoc {
  const InvoiceDoc({
    required this.invoice,
    required this.business,
    required this.settings,
    required this.withholdingRate,
    this.vatRate,
    this.hours = const [],
    this.logo,
    this.qr,
    this.paid = false,
    this.attachedPages = const [],
  });

  final StoredInvoice invoice;
  final String business;
  final DocumentSettings settings;
  final BasisPoints withholdingRate;
  final BasisPoints? vatRate;

  /// The hours billed, for the timesheet page.
  final List<HourEntry> hours;
  final Uint8List? logo;
  final Uint8List? qr;

  /// Shows a Paid stamp.
  final bool paid;

  /// Attached documents as page pictures, in order, for one PDF.
  final List<Uint8List> attachedPages;

  /// The same, without the attached pages, for separate files.
  InvoiceDoc withoutAttachedPages() => InvoiceDoc(
    invoice: invoice,
    business: business,
    settings: settings,
    withholdingRate: withholdingRate,
    vatRate: vatRate,
    hours: hours,
    logo: logo,
    qr: qr,
    paid: paid,
  );

  String fileName(String part) =>
      '${invoice.number.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-')}'
      '${part.isEmpty ? '' : '-$part'}.pdf';
}

String _date(CalendarDate d) => periodText(ReportPeriod(d, d.addDays(1), ''));

/// The invoice as an A4 PDF, in the app's report style, with the timesheet
/// as its own page when [withTimesheet] and the invoice asks for it.
Future<Uint8List> renderInvoicePdf(
  InvoiceDoc doc, {
  bool withInvoice = true,
  bool withTimesheet = true,
}) {
  final brand = PdfColor.fromInt(BrandTokens.brand.toARGB32());
  final text = PdfColor.fromInt(BrandTokens.text.toARGB32());
  final muted = PdfColor.fromInt(BrandTokens.textMuted.toARGB32());
  final border = PdfColor.fromInt(BrandTokens.border.toARGB32());
  final soft = PdfColor.fromInt(BrandTokens.brandSoft.toARGB32());
  final success = PdfColor.fromInt(BrandTokens.success.toARGB32());
  final i = doc.invoice;
  final s = doc.settings;
  final t = i.totals;
  String plain(int minor) => formatMoney(Money(minor), withCurrency: false);
  String money(int minor) => minor < 0 ? '- ${plain(-minor)}' : plain(minor);
  final theme = pw.ThemeData.base();
  final pdf = pw.Document(
    title: _latin1('Invoice ${i.number}'),
    author: _latin1(doc.business),
    creator: 'Pesa Clarity',
    producer: 'Pesa Clarity',
  );

  pw.Widget footer(pw.Context context) => pw.Column(
    children: [
      pw.Divider(color: border),
      pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Made on this phone with Pesa Clarity. This is not an eTIMS tax '
              'invoice.',
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
  );

  pw.Widget strip(pw.Context context) => pw.Column(
    children: [
      pw.Container(height: 4, color: brand),
      pw.SizedBox(height: 24),
    ],
  );

  pw.Widget mark() => doc.logo != null
      ? pw.Image(pw.MemoryImage(doc.logo!), height: 40)
      : pw.Container(
          width: 40,
          height: 40,
          alignment: pw.Alignment.center,
          decoration: pw.BoxDecoration(
            color: brand,
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(
            _latin1(DocumentSettings.initials(doc.business)),
            style: const pw.TextStyle(
              color: PdfColors.white,
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );

  pw.Widget row(
    String a,
    String b, {
    String? detail,
    bool bold = false,
    PdfColor? color,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _latin1(a),
                style: pw.TextStyle(
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: color,
                ),
              ),
              if (detail != null && detail.isNotEmpty)
                pw.Text(
                  _latin1(detail),
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
            ],
          ),
        ),
        pw.Text(
          b,
          style: pw.TextStyle(
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      ],
    ),
  );

  final fees = [
    for (final l in i.lines)
      if (l.kind == InvoiceLineKind.fees) l,
  ];
  final costs = [
    for (final l in i.lines)
      if (l.kind == InvoiceLineKind.cost) l,
  ];
  final wRate = rateText(doc.withholdingRate);
  final account = s.till == null ? null : '${s.till} · account ${i.number}';

  if (withInvoice) {
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 0, 40, 28),
        theme: theme.copyWith(
          defaultTextStyle: theme.defaultTextStyle.copyWith(
            color: text,
            fontSize: 10,
          ),
        ),
        header: strip,
        footer: footer,
        build: (context) => [
          pw.Stack(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  mark(),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          _latin1(doc.business),
                          style: const pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        for (final line in [
                          [?s.place, ?s.phone].join(' · '),
                          ?s.email,
                          if (s.showKraPin && s.kraPin != null)
                            'KRA PIN ${s.kraPin}',
                        ])
                          if (line.isNotEmpty)
                            pw.Text(
                              _latin1(line),
                              style: pw.TextStyle(color: muted),
                            ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'INVOICE',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: brand,
                        ),
                      ),
                      pw.Text(_latin1(i.number)),
                      pw.Text(
                        _latin1('Issued ${_date(i.issuedOn)}'),
                        style: pw.TextStyle(color: muted),
                      ),
                      if (i.dueOn case final due?)
                        pw.Text(
                          _latin1('Due ${_date(due)}'),
                          style: const pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              if (doc.paid)
                pw.Positioned(
                  right: 120,
                  top: 4,
                  child: pw.Transform.rotate(
                    angle: -math.pi / 12,
                    child: pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: success, width: 2),
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Text(
                        'PAID',
                        style: pw.TextStyle(
                          color: success,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text('BILL TO', style: pw.TextStyle(fontSize: 8, color: muted)),
          pw.Text(
            _latin1(i.client),
            style: const pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            color: soft,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Text(
                    'Fees',
                    style: pw.TextStyle(fontSize: 8, color: muted),
                  ),
                ),
                pw.Text(
                  _latin1(i.currency),
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6),
            child: pw.Column(
              children: [
                for (final l in fees)
                  row(l.name, plain(l.amountMinor), detail: l.detail),
                if (t.feesShownMinor != t.feesMinor)
                  row(
                    'Withholding tax paid on top ($wRate)',
                    plain(t.feesShownMinor - t.feesMinor),
                    detail:
                        'So that after tax the fees are '
                        '${plain(t.feesMinor)}',
                  ),
              ],
            ),
          ),
          if (costs.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Container(
              color: soft,
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
              child: pw.Text(
                'Costs passed on',
                style: pw.TextStyle(fontSize: 8, color: muted),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6),
              child: pw.Column(
                children: [
                  for (final l in costs)
                    row(l.name, plain(l.amountMinor), detail: l.detail),
                ],
              ),
            ),
          ],
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pw.Spacer(),
              pw.SizedBox(
                width: 240,
                child: pw.Column(
                  children: [
                    pw.Divider(color: border),
                    row('Fees', plain(t.feesShownMinor)),
                    if (t.costsMinor > 0) row('Costs', plain(t.costsMinor)),
                    if (t.discountMinor > 0)
                      row('Discount', money(-t.discountMinor)),
                    if (t.vatMinor > 0 && doc.vatRate != null)
                      row('VAT (${rateText(doc.vatRate!)})', plain(t.vatMinor)),
                    row('Total', plain(t.totalMinor), bold: true),
                    if (t.withheldMinor > 0)
                      row(
                        'Withholding tax ($wRate), the client pays to KRA',
                        money(-t.withheldMinor),
                      ),
                    pw.Divider(color: text),
                    row(
                      'To pay',
                      '${i.currency} ${plain(t.toPayMinor)}',
                      bold: true,
                      color: brand,
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          if (account != null || s.bank != null || doc.qr != null)
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: border),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'HOW TO PAY',
                          style: pw.TextStyle(fontSize: 8, color: muted),
                        ),
                        pw.SizedBox(height: 4),
                        if (account != null) pw.Text(_latin1(account)),
                        if (s.bank case final bank?) pw.Text(_latin1(bank)),
                      ],
                    ),
                  ),
                  if (doc.qr != null)
                    pw.Column(
                      children: [
                        pw.Image(pw.MemoryImage(doc.qr!), width: 80),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Scan with the M-PESA app',
                          style: pw.TextStyle(fontSize: 7, color: muted),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          if (i.notes case final notes? when notes.isNotEmpty) ...[
            pw.SizedBox(height: 12),
            pw.Text(_latin1(notes), style: pw.TextStyle(color: muted)),
          ],
        ],
      ),
    );
  }

  if (withTimesheet && i.timesheet && doc.hours.isNotEmpty) {
    final days = <CalendarDate, List<HourEntry>>{};
    for (final e in doc.hours) {
      days.putIfAbsent(e.day, () => []).add(e);
    }
    final order = days.keys.toList()..sort();
    final first = order.first;
    final last = order.last;
    pw.TableRow cells(
      List<String> c, {
      bool bold = false,
      PdfColor? fill,
    }) => pw.TableRow(
      decoration: fill == null ? null : pw.BoxDecoration(color: fill),
      children: [
        for (final (n, v) in c.indexed)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            child: pw.Text(
              _latin1(v),
              textAlign: n >= 3 ? pw.TextAlign.right : pw.TextAlign.left,
              style: pw.TextStyle(
                fontSize: fill == null ? 9 : 8,
                color: fill == null ? text : muted,
                fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
      ],
    );
    final projects = byProject(doc.hours);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(40, 0, 40, 28),
        theme: theme.copyWith(
          defaultTextStyle: theme.defaultTextStyle.copyWith(
            color: text,
            fontSize: 10,
          ),
        ),
        header: strip,
        footer: footer,
        build: (context) => [
          pw.Text(
            'Timesheet',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: brand,
            ),
          ),
          pw.Text(
            _latin1(
              'Invoice ${i.number} · ${i.client} · '
              '${periodText(ReportPeriod(first, last.addDays(1), ''))}',
            ),
            style: pw.TextStyle(color: muted),
          ),
          pw.Text(_latin1(doc.business), style: pw.TextStyle(color: muted)),
          pw.SizedBox(height: 12),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(1.3),
              1: pw.FlexColumnWidth(2.6),
              2: pw.FlexColumnWidth(1.8),
              3: pw.FlexColumnWidth(0.8),
              4: pw.FlexColumnWidth(1.1),
            },
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: border, width: 0.5),
            ),
            children: [
              cells([
                'Day',
                'What',
                'Project',
                'Hours',
                i.currency,
              ], fill: soft),
              for (final d in order) ...[
                for (final (n, e) in days[d]!.indexed)
                  cells([
                    if (n == 0)
                      '${weekdayName(d).substring(0, 3)} ${shortDate(d)}'
                    else
                      '',
                    e.what,
                    e.project ?? '',
                    hoursText(e.minutes),
                    e.amountMinor == 0 ? '' : plain(e.amountMinor),
                  ]),
                cells([
                  '',
                  'Day total',
                  '',
                  hoursText(days[d]!.fold(0, (a, e) => a + e.minutes)),
                  plain(days[d]!.fold(0, (a, e) => a + e.amountMinor)),
                ], bold: true),
              ],
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(5.7),
              1: pw.FlexColumnWidth(0.8),
              2: pw.FlexColumnWidth(1.1),
            },
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: border, width: 0.5),
            ),
            children: [
              for (final p in projects)
                pw.TableRow(
                  children: [
                    for (final (n, v) in [
                      p.project ?? 'Hours',
                      hoursText(p.minutes),
                      plain(p.amountMinor),
                    ].indexed)
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          _latin1(v),
                          textAlign: n > 0
                              ? pw.TextAlign.right
                              : pw.TextAlign.left,
                        ),
                      ),
                  ],
                ),
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  border: pw.Border(top: pw.BorderSide(color: text)),
                ),
                children: [
                  for (final (n, v) in [
                    'Total · ${order.length} days',
                    hoursText(
                      doc.hours
                          .where((e) => e.billable)
                          .fold(0, (a, e) => a + e.minutes),
                    ),
                    plain(doc.hours.fold(0, (a, e) => a + e.amountMinor)),
                  ].indexed)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(
                        _latin1(v),
                        textAlign: n > 0
                            ? pw.TextAlign.right
                            : pw.TextAlign.left,
                        style: const pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
  for (final page in withInvoice ? doc.attachedPages : const <Uint8List>[]) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => pw.Center(child: pw.Image(pw.MemoryImage(page))),
      ),
    );
  }
  return pdf.save();
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
