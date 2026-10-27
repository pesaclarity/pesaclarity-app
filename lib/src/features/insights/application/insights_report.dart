import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/health/health_index.dart';
import '../../../domain/insights/insights_summary.dart';
import '../../../domain/insights/leakage.dart';
import '../../../domain/tags/tag_totals.dart';
import '../../../domain/time/calendar.dart';
import '../../../theme/brand_tokens.dart';
import 'month_labels.dart';

/// A tag and what was spent under it this month.
typedef TagSpend = ({String name, int spendingMinor});

/// Everything on the one-page Insights report.
class InsightsReport {
  const InsightsReport({
    required this.summary,
    required this.createdAt,
    this.health,
    this.healthChange,
    this.tags = const [],
  });

  final InsightsSummary summary;
  final DateTime createdAt;

  /// The last full month's index, when that month has transactions.
  final HealthIndex? health;
  final int? healthChange;

  /// Largest first.
  final List<TagSpend> tags;

  YearMonth get month => summary.current.month;

  String get title => 'Pesa Clarity report, ${monthName(month)} ${month.year}';

  /// For example `pesa-clarity-report-2026-10.pdf`.
  String get fileName => 'pesa-clarity-report-$month.pdf';
}

/// Most tags the report lists, so it stays on one page.
const reportTagLimit = 6;

/// Turns a report into PDF bytes; widget tests swap in a stand-in, since
/// rendering runs in a background isolate.
final reportRendererProvider =
    Provider<Future<Uint8List> Function(InsightsReport)>(
      (ref) => renderInsightsReport,
    );

/// Renders [report] as a one-page A4 PDF.
Future<Uint8List> renderInsightsReport(InsightsReport report) {
  final brand = PdfColor.fromInt(BrandTokens.brand.toARGB32());
  final text = PdfColor.fromInt(BrandTokens.text.toARGB32());
  final muted = PdfColor.fromInt(BrandTokens.textMuted.toARGB32());
  final border = PdfColor.fromInt(BrandTokens.border.toARGB32());
  final soft = PdfColor.fromInt(BrandTokens.brandSoft.toARGB32());

  final summary = report.summary;
  final current = summary.current;
  final previous = summary.previous;
  final month = report.month;
  final today = CalendarDate.nairobi(report.createdAt);

  String kes(int minor) => formatMoney(Money(minor), withCurrency: false);

  pw.Widget heading(String label) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
    child: pw.Text(
      label,
      style: const pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
    ),
  );

  pw.Widget stat(String label, String value, {String? note}) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: border),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 9, color: muted)),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: const pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (note != null) ...[
            pw.SizedBox(height: 2),
            pw.Text(note, style: pw.TextStyle(fontSize: 9, color: brand)),
          ],
        ],
      ),
    ),
  );

  pw.Widget barRow(
    String label,
    String value,
    double fraction, {
    PdfColor? color,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 5),
    child: pw.Row(
      children: [
        pw.SizedBox(
          width: 90,
          child: pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
        ),
        pw.Expanded(
          child: pw.Stack(
            children: [
              pw.Container(
                height: 6,
                decoration: pw.BoxDecoration(
                  color: border,
                  borderRadius: pw.BorderRadius.circular(3),
                ),
              ),
              pw.Row(
                children: [
                  if (fraction > 0)
                    pw.Expanded(
                      flex: (fraction * 1000).round().clamp(1, 1000),
                      child: pw.Container(
                        height: 6,
                        decoration: pw.BoxDecoration(
                          color: color ?? brand,
                          borderRadius: pw.BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  if (fraction < 1)
                    pw.Expanded(
                      flex: ((1 - fraction) * 1000).round().clamp(1, 1000),
                      child: pw.SizedBox(height: 6),
                    ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(
          width: 70,
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );

  final share = current.leakageShareBasisPoints;
  final groups = current.leakage.groups;
  final largestGroup = groups.fold(
    0,
    (m, g) => g.amountMinor > m ? g.amountMinor : m,
  );
  final largestMonth = summary.trend.fold(
    0,
    (m, x) => x.spendingMinor > m ? x.spendingMinor : m,
  );
  final health = report.health;
  final action = health?.bestAction;
  final tags = report.tags.take(reportTagLimit).toList();
  final largestTag = tags.fold(
    0,
    (m, t) => t.spendingMinor > m ? t.spendingMinor : m,
  );

  double fractionOf(int value, int largest) =>
      value <= 0 || largest <= 0 ? 0 : value / largest;

  final theme = pw.ThemeData.base();
  final doc = pw.Document(
    title: report.title,
    creator: 'Pesa Clarity',
    producer: 'Pesa Clarity',
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      theme: theme.copyWith(
        defaultTextStyle: theme.defaultTextStyle.copyWith(
          color: text,
          fontSize: 10,
        ),
      ),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            _latin1(report.title),
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: brand,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${monthName(month)} ${month.year}, up to ${longDate(today)}. '
            'Amounts in ${BaseCurrency.code}.',
            style: pw.TextStyle(color: muted),
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              stat('Income', kes(current.incomeMinor)),
              pw.SizedBox(width: 8),
              stat('Spending and fees', kes(current.spendingMinor)),
              pw.SizedBox(width: 8),
              stat(
                'Leakage',
                kes(current.leakageMinor),
                note: share == null ? null : '${percentLabel(share)} of income',
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: soft,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              leakageSentence(
                summary,
                previousMonthName: previous == null
                    ? null
                    : monthName(previous.month),
              ),
            ),
          ),
          heading('Where it goes'),
          for (final g in groups)
            barRow(
              g.label,
              kes(g.amountMinor),
              fractionOf(g.amountMinor, largestGroup),
            ),
          heading('Spending, last ${summary.trend.length} months'),
          for (final m in summary.trend)
            barRow(
              '${shortMonthName(m.month)} ${m.month.year}',
              kes(m.spendingMinor),
              fractionOf(m.spendingMinor, largestMonth),
              color: m == current ? brand : muted,
            ),
          heading(
            health == null
                ? 'Financial Health Index'
                : 'Financial Health Index, '
                      '${monthName(health.month)} ${health.month.year}',
          ),
          if (health == null)
            pw.Text(
              'Shows once a full month of transactions has been read.',
              style: pw.TextStyle(color: muted),
            )
          else ...[
            pw.Text(
              '${health.score} of 100, ${health.band.label}.'
              '${healthChangeSentence(report.healthChange)}',
              style: const pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 6),
            for (final pillar in HealthPillar.values)
              barRow(
                pillar.label,
                '${pillarPoints(health, pillar)} of 25',
                health.pillarCentipoints(pillar) / 2500,
              ),
            if (action != null) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                'What helps most: ${_latin1(action.message)} '
                '(up to ${action.gainPoints} points)',
              ),
            ],
          ],
          heading('Tags in ${monthName(month)}'),
          if (tags.isEmpty)
            pw.Text(
              'Tagged spending shows here, such as #roadtrip or #wedding.',
              style: pw.TextStyle(color: muted),
            )
          else
            for (final t in tags)
              barRow(
                '#${_latin1(t.name)}',
                kes(t.spendingMinor),
                fractionOf(t.spendingMinor, largestTag),
              ),
          pw.Spacer(),
          pw.Divider(color: border),
          pw.Text(
            'Made on this phone by Pesa Clarity on ${longDate(today)}. '
            'Leakages are spending on payees marked lifestyle, friends or '
            'family, plus fees.',
            style: pw.TextStyle(fontSize: 8, color: muted),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

/// "Up 19,200 on September. Cutting half frees 15,000 a month."
String leakageSentence(InsightsSummary summary, {String? previousMonthName}) {
  String kes(int minor) => formatMoney(Money(minor), withCurrency: false);
  final change = summary.leakageChangeMinor;
  final parts = <String>[];
  if (previousMonthName != null && summary.previous!.entryCount > 0) {
    parts.add(switch (change) {
      > 0 => 'Up ${kes(change)} on $previousMonthName.',
      < 0 => 'Down ${kes(-change)} on $previousMonthName.',
      _ => 'Same as $previousMonthName.',
    });
  }
  if (summary.halfLeakageMinor > 0) {
    parts.add('Cutting half frees ${kes(summary.halfLeakageMinor)} a month.');
  } else if (summary.current.leakageMinor == 0) {
    parts.add('Leakages are low this month.');
  }
  return parts.join(' ');
}

/// " Up 3 on the month before." or empty without a change to report.
String healthChangeSentence(int? change) => switch (change) {
  null => '',
  > 0 => ' Up $change on the month before.',
  < 0 => ' Down ${-change} on the month before.',
  _ => ' Same as the month before.',
};

/// A pillar's points out of 25, rounded to whole points.
int pillarPoints(HealthIndex index, HealthPillar pillar) =>
    (index.pillarCentipoints(pillar) + 50) ~/ 100;

/// The built-in PDF fonts cover Latin-1 only.
String _latin1(String s) =>
    String.fromCharCodes(s.runes.map((r) => r > 0xFF ? 0x3F : r));

/// Tag totals with their names, largest spending first.
List<TagSpend> tagSpends(Map<int, TagSummary> totals, Map<int, String> names) =>
    [
      for (final s in totals.values)
        (
          name: names[s.tagId] ?? '${s.tagId}',
          spendingMinor: s.totals.spendingMinor,
        ),
    ]..sort((a, b) {
      final bySpend = b.spendingMinor.compareTo(a.spendingMinor);
      return bySpend != 0 ? bySpend : a.name.compareTo(b.name);
    });
