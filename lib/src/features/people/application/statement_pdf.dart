import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/documents_repository.dart';
import '../../../domain/books/business_report.dart'
    show ReportPeriod, periodText;
import '../../../domain/documents/document_settings.dart';
import '../../../domain/people/people.dart';
import '../../../domain/time/calendar.dart';
import '../../../theme/brand_tokens.dart';
import '../../documents/application/document_providers.dart';
import '../../insights/application/report_sharer.dart';
import '../../spaces/application/spaces_providers.dart';

String _date(CalendarDate d) => periodText(ReportPeriod(d, d.addDays(1), ''));

/// A customer's statement as an A4 PDF: what they owe, and every credit
/// sale and payment with the balance after each, oldest first.
Future<Uint8List> renderStatementPdf({
  required CustomerAccount customer,
  required String business,
  required DocumentSettings settings,
  required CalendarDate today,
  Uint8List? logo,
}) {
  final brand = PdfColor.fromInt(BrandTokens.brand.toARGB32());
  final text = PdfColor.fromInt(BrandTokens.text.toARGB32());
  final muted = PdfColor.fromInt(BrandTokens.textMuted.toARGB32());
  final border = PdfColor.fromInt(BrandTokens.border.toARGB32());
  final soft = PdfColor.fromInt(BrandTokens.brandSoft.toARGB32());
  String plain(int minor) {
    final p = formatMoney(Money(minor.abs()), withCurrency: false);
    return minor < 0 ? '- $p' : p;
  }

  final lines = [...customer.history]..sort((a, b) => a.date.compareTo(b.date));
  final rows = <List<String>>[];
  var balance = 0;
  for (final l in lines) {
    balance += l.amountMinor;
    rows.add([_date(l.date), l.label, plain(l.amountMinor), plain(balance)]);
  }
  final theme = pw.ThemeData.base();
  final doc = pw.Document(
    title: _latin1('Statement for ${customer.name}'),
    author: _latin1(business),
    creator: 'Pesa Clarity',
    producer: 'Pesa Clarity',
  );
  pw.Widget cell(String v, {bool right = false, bool head = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: pw.Text(
          _latin1(v),
          textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
          style: pw.TextStyle(
            fontSize: head ? 8 : 10,
            color: head ? muted : text,
          ),
        ),
      );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 0, 40, 28),
      theme: theme.copyWith(
        defaultTextStyle: theme.defaultTextStyle.copyWith(
          color: text,
          fontSize: 10,
        ),
      ),
      header: (context) => pw.Column(
        children: [
          pw.Container(height: 4, color: brand),
          pw.SizedBox(height: 24),
        ],
      ),
      footer: (context) => pw.Column(
        children: [
          pw.Divider(color: border),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Made on this phone with Pesa Clarity on ${_date(today)}.',
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
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null) ...[
              pw.Image(pw.MemoryImage(logo), height: 40),
              pw.SizedBox(width: 12),
            ],
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _latin1(business),
                    style: const pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  if ([?settings.place, ?settings.phone].isNotEmpty)
                    pw.Text(
                      _latin1([?settings.place, ?settings.phone].join(' · ')),
                      style: pw.TextStyle(color: muted),
                    ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'STATEMENT',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: brand,
                  ),
                ),
                pw.Text(
                  _latin1('As of ${_date(today)}'),
                  style: pw.TextStyle(color: muted),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Text('FOR', style: pw.TextStyle(fontSize: 8, color: muted)),
        pw.Text(
          _latin1(customer.name),
          style: const pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(1.6),
            1: pw.FlexColumnWidth(3),
            2: pw.FlexColumnWidth(1.3),
            3: pw.FlexColumnWidth(1.3),
          },
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(color: border, width: 0.5),
          ),
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: soft),
              children: [
                cell('Date', head: true),
                cell('What', head: true),
                cell('Amount', right: true, head: true),
                cell('Balance', right: true, head: true),
              ],
            ),
            for (final r in rows)
              pw.TableRow(
                children: [
                  cell(r[0]),
                  cell(r[1]),
                  cell(r[2], right: true),
                  cell(r[3], right: true),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Row(
          children: [
            pw.Spacer(),
            pw.Text(
              _latin1('Owes ${BaseCurrency.code} ${plain(customer.owedMinor)}'),
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: brand,
              ),
            ),
          ],
        ),
        if (settings.payLine case final pay?) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            _latin1('How to pay: $pay'),
            style: pw.TextStyle(color: muted),
          ),
        ],
      ],
    ),
  );
  return doc.save();
}

/// Shares a customer's statement as a PDF.
class StatementSender {
  StatementSender(this._ref);

  final Ref _ref;

  Future<void> share(CustomerAccount customer) async {
    final settings = await _ref.read(documentSettingsProvider.future);
    final logo = await _ref.read(
      documentFileProvider(DocumentFileKind.logo).future,
    );
    final business = settings.nameOr(_ref.read(activeSpaceProvider).name);
    final today = CalendarDate.local(_ref.read(clockProvider)());
    final pdf = await _ref.read(statementRendererProvider)(
      customer: customer,
      business: business,
      settings: settings,
      today: today,
      logo: logo != null && logo.isImage ? logo.bytes : null,
    );
    final slug = customer.name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    await _ref
        .read(reportSharerProvider)
        .sharePdf(
          pdf,
          fileName: 'statement-$slug-$today.pdf',
          subject: 'Statement for ${customer.name}',
        );
  }
}

/// Renders a statement; tests swap in a stand-in.
final statementRendererProvider =
    Provider<
      Future<Uint8List> Function({
        required CustomerAccount customer,
        required String business,
        required DocumentSettings settings,
        required CalendarDate today,
        Uint8List? logo,
      })
    >((ref) => renderStatementPdf);

final statementSenderProvider = Provider<StatementSender>(StatementSender.new);

/// The built-in PDF fonts cover Latin-1 only.
String _latin1(String s) => String.fromCharCodes(
  s
      .replaceAll('−', '-')
      .replaceAll(RegExp('[‘’]'), "'")
      .replaceAll(RegExp('[–—]'), '-')
      .runes
      .map((r) => r > 0xFF ? 0x3F : r),
);
