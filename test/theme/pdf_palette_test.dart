import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pesaclarity/src/core/export/export_table.dart';
import 'package:pesaclarity/src/core/export/pdf_encoder.dart';
import 'package:pesaclarity/src/core/money/money.dart';
import 'package:pesaclarity/src/data/repositories/invoices_repository.dart';
import 'package:pesaclarity/src/domain/books/business_report.dart';
import 'package:pesaclarity/src/domain/books/report_setup.dart';
import 'package:pesaclarity/src/domain/documents/document_settings.dart';
import 'package:pesaclarity/src/domain/documents/invoice.dart';
import 'package:pesaclarity/src/domain/documents/receipt.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/people/people.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/business_insights/application/business_report_pdf.dart';
import 'package:pesaclarity/src/features/business_insights/application/report_content.dart';
import 'package:pesaclarity/src/features/documents/application/receipt_pdf.dart';
import 'package:pesaclarity/src/features/invoices/application/invoice_pdf.dart';
import 'package:pesaclarity/src/features/people/application/statement_pdf.dart';
import 'package:pesaclarity/src/theme/brand_tokens.dart';
import 'package:pesaclarity/src/theme/pdf_palette.dart';
import 'package:pesaclarity/src/theme/pesa_colors.dart';

PdfColor _pdf(int argb) => PdfColor.fromInt(argb);

/// Every fill and stroke colour a PDF's pages set, read from its content
/// streams (`r g b rg` and `r g b RG`).
Set<String> _colours(Uint8List pdf) {
  final bytes = latin1.decode(pdf);
  final found = <String>{};
  final streams = RegExp(r'stream\r?\n').allMatches(bytes);
  for (final m in streams) {
    final end = bytes.indexOf('endstream', m.end);
    if (end < 0) continue;
    final raw = pdf.sublist(m.end, end);
    String content;
    try {
      content = latin1.decode(zlib.decode(raw));
    } on FormatException {
      content = latin1.decode(raw);
    }
    for (final c in RegExp(
      r'(-?[\d.]+) (-?[\d.]+) (-?[\d.]+) (?:rg|RG)\b',
    ).allMatches(content)) {
      found.add(
        [
          for (var i = 1; i <= 3; i++)
            double.parse(c.group(i)!).toStringAsFixed(3),
        ].join(' '),
      );
    }
  }
  return found;
}

String _key(PdfColor c) =>
    [c.red, c.green, c.blue].map((v) => v.toStringAsFixed(3)).join(' ');

void _expectFrom(Uint8List pdf, PdfPalette palette, String what) {
  final allowed = palette.all.map(_key).toSet();
  final used = _colours(pdf);
  expect(used, isNotEmpty, reason: what);
  expect(
    used.difference(allowed),
    isEmpty,
    reason: '$what uses colours outside its palette',
  );
}

void main() {
  test('the light palette is built from the light theme', () {
    final p = PdfPalette.light;
    expect(p.accent, _pdf(BrandTokens.brand.toARGB32()));
    expect(p.text, _pdf(BrandTokens.text.toARGB32()));
    expect(p.muted, _pdf(PesaColors.light.textMuted.toARGB32()));
    expect(p.headerFill, _pdf(PesaColors.light.selected.toARGB32()));
    expect(p.success, _pdf(PesaColors.light.successText.toARGB32()));
    // The brand tint is gone: text, lines, headers and boxes are pure greys.
    for (final c in [p.text, p.muted, p.line, p.headerFill!, p.panel!, p.bar]) {
      expect(c.red, c.green, reason: _key(c));
      expect(c.green, c.blue, reason: _key(c));
    }
    expect(p.all.map(_key), isNot(contains(_key(_pdf(0xFFFDECEE)))));
    // Red is only the accent.
    expect(
      p.all.where((c) => _key(c) == _key(p.accent)),
      hasLength(1),
      reason: 'nothing but the accent is brand red',
    );
  });

  test('formal and black and white keep the owner choices', () {
    expect(PdfPalette.report(ReportColour.brand), same(PdfPalette.light));
    expect(
      PdfPalette.report(ReportColour.formal).accent,
      PdfPalette.light.text,
    );
    expect(PdfPalette.receipt(blackAndWhite: false), same(PdfPalette.light));
    final mono = PdfPalette.receipt(blackAndWhite: true);
    expect(mono.headerFill, isNull);
    expect(mono.successFill, isNull);
    expect(mono.all.map(_key).toSet(), {
      _key(PdfColors.black),
      _key(PdfColors.white),
    });
  });

  test('no PDF builder picks its own colours', () {
    final builders = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.endsWith('pdf_palette.dart') &&
            f.readAsStringSync().contains("import 'package:pdf/"))
          f,
    ];
    expect(builders.length, greaterThanOrEqualTo(8));
    final literal = RegExp(
      r'PdfColor\(|PdfColor\.from|PdfColors\.|BrandTokens\.|Color\(0x|PesaColors',
    );
    for (final f in builders) {
      expect(
        literal.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '${f.path} should take its colours from PdfPalette',
      );
    }
  });

  group('the PDFs draw only in their palette', () {
    final invoice = StoredInvoice(
      id: 1,
      number: 'AC-INV-0001',
      client: 'Test Client Ltd',
      issuedOn: CalendarDate(2026, 11, 13),
      billBy: BillBy.items,
      hoursDetail: HoursDetail.total,
      timesheet: false,
      withholding: Withholding.none,
      totals: invoiceTotals(
        feesMinor: 1500000,
        costsMinor: 0,
        withholding: Withholding.none,
        withholdingRate: 500,
      ),
      currency: 'KES',
      lines: const [
        InvoiceLine(
          kind: InvoiceLineKind.fees,
          name: 'Website work',
          amountMinor: 1500000,
        ),
      ],
    );

    for (final header in InvoiceHeader.values) {
      test('an invoice with a ${header.label.toLowerCase()}', () async {
        final pdf = await renderInvoicePdf(
          InvoiceDoc(
            invoice: invoice,
            business: 'Test Consulting',
            settings: DocumentSettings(
              till: 'Paybill 000000',
              invoiceHeader: header,
              signature: true,
            ),
            withholdingRate: 500,
            paid: true,
          ),
        );
        _expectFrom(pdf, PdfPalette.light, 'invoice');
      });
    }

    for (final mono in [false, true]) {
      test('a receipt${mono ? ' in black and white' : ''}', () async {
        final pdf = await renderReceiptPdf(
          Receipt(
            number: 'TS-000001',
            at: DateTime.utc(2026, 11, 13, 9),
            business: 'Test stall',
            lines: const [
              ReceiptLine(
                name: 'Sukuma',
                quantityMilli: 1000,
                totalMinor: 2000,
              ),
            ],
            totalMinor: 2000,
            payments: const [
              ReceiptPayment(method: SalePaymentMethod.cash, amountMinor: 2000),
            ],
            currency: 'KES',
            blackAndWhite: mono,
          ),
          label: (m) => m.name,
          initials: 'TS',
        );
        _expectFrom(pdf, PdfPalette.receipt(blackAndWhite: mono), 'receipt');
      });
    }

    test('a customer statement', () async {
      final pdf = await renderStatementPdf(
        customer: CustomerAccount(
          name: 'Test Customer',
          owedMinor: 150000,
          overTwoWeeksMinor: 0,
          history: [
            StatementLine(
              date: CalendarDate(2026, 11, 2),
              label: 'Credit sale',
              amountMinor: 150000,
            ),
          ],
        ),
        business: 'Test stall',
        settings: const DocumentSettings(till: 'Till 000000'),
        today: CalendarDate(2026, 11, 13),
      );
      _expectFrom(pdf, PdfPalette.light, 'statement');
    });

    for (final colour in ReportColour.values) {
      for (final cover in ReportCoverStyle.values) {
        test('a business report, ${colour.label}, ${cover.name}', () async {
          final pdf = await renderBusinessReport(
            ReportDocument(
              title: 'Profit and loss',
              business: 'Test stall',
              coverLine: 'Test stall',
              period: ReportPeriod(
                CalendarDate(2026, 10, 1),
                CalendarDate(2026, 11, 1),
                'October',
              ),
              made: CalendarDate(2026, 11, 13),
              currency: 'KES',
              style: ReportStyle(colour: colour, cover: cover, signature: true),
              blocks: const [
                ReportTable(
                  'Sales',
                  columns: ['Item', 'Amount'],
                  rows: [
                    ['Sukuma', 200000],
                  ],
                  total: ['Total', 200000],
                ),
                ReportNotes('Notes', ['Sales were steady.']),
                ReportChart(
                  'By month',
                  columns: true,
                  points: [ReportPoint('Sep', -1000), ReportPoint('Oct', 5000)],
                ),
                ReportChart('By item', points: [ReportPoint('Sukuma', 5000)]),
              ],
            ),
          );
          _expectFrom(pdf, PdfPalette.report(colour), 'report');
        });
      }
    }

    test('an export', () async {
      final pdf = await encodePdf(
        ExportWorkbook(
          title: 'Transactions',
          tables: [
            ExportTable(
              title: 'Transactions',
              columns: ['Date', 'Amount'],
              rows: [
                ['2026-11-01', Money(1000)],
              ],
            ),
          ],
        ),
        createdAt: DateTime.utc(2026, 11, 13),
      );
      _expectFrom(pdf, PdfPalette.light, 'export');
    });
  });
}
