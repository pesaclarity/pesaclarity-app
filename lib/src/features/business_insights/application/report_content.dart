import 'dart:typed_data';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/books/cash_book.dart';
import '../../../domain/books/report_setup.dart';
import '../../../domain/enums.dart';
import '../../../domain/ledger/activity_lines.dart';
import '../../../domain/stock/stock.dart';
import '../../../domain/tax/tax_estimate.dart';
import '../../../domain/tax/tax_pack.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/format/date_labels.dart';
import '../../../shared/format/ledger_labels.dart';
import '../../sales/presentation/pay_sheet.dart';
import '../../tax/application/tax_providers.dart';
import 'business_report_providers.dart';

/// A part of a report.
sealed class ReportBlock {
  const ReportBlock(this.title);

  final String title;
}

/// A table. Each cell is text, money in minor units (an int), a
/// [CalendarDate], or empty.
class ReportTable extends ReportBlock {
  const ReportTable(
    super.title, {
    required this.columns,
    required this.rows,
    this.total,
    this.note,
  });

  final List<String> columns;
  final List<List<Object?>> rows;
  final List<Object?>? total;
  final String? note;
}

/// Sentences, one per line.
class ReportNotes extends ReportBlock {
  const ReportNotes(super.title, this.lines);

  final List<String> lines;
}

/// A finished report, ready to print as a PDF or write as CSV.
class ReportDocument {
  const ReportDocument({
    required this.title,
    required this.business,
    required this.coverLine,
    required this.period,
    required this.made,
    required this.currency,
    required this.blocks,
    this.logo,
  });

  final String title;
  final String business;
  final String coverLine;
  final ReportPeriod period;
  final CalendarDate made;
  final String currency;
  final List<ReportBlock> blocks;

  /// The business's logo for the cover, when it has one.
  final Uint8List? logo;

  String get periodLine => periodText(period);

  /// For example `vegetable-stall-report-2026-11-01-to-2026-11-30.pdf`.
  String fileName(String extension) {
    final slug = business
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return '${slug.isEmpty ? 'business' : slug}-report-'
        '${period.from}-to-${period.lastDay}.$extension';
  }
}

/// The [sections] of [report], in print order.
ReportDocument reportDocument({
  required BusinessReport report,
  required Set<ReportSection> sections,
  required String title,
  required String business,
  required String coverLine,
  required CalendarDate today,
  CashBook? cashBook,
  TaxView? tax,
  ReportDetail detail = ReportDetail.everyEntry,
  Uint8List? logo,
  Map<int, String> accountNames = const {},
  Map<int, String> categoryNames = const {},
}) {
  final period = report.period;
  final endsBefore = period.lastDay.isBefore(today);
  final asOfToday = endsBefore ? 'As they stand on ${_day(today)}.' : null;
  final blocks = <ReportBlock>[];
  for (final section in ReportSection.values) {
    if (!sections.contains(section)) continue;
    switch (section) {
      case ReportSection.profitAndLoss:
        final pnl = report.pnl;
        blocks.add(
          ReportTable(
            section.label,
            columns: const ['', 'Amount'],
            rows: [
              for (final l in pnl.income) [l.name, l.amountMinor],
              for (final l in pnl.costs) [l.name, -l.amountMinor],
            ],
            total: ['Profit', pnl.profitMinor],
          ),
        );
      case ReportSection.byWay:
        final total = report.salesMinor;
        blocks.add(
          ReportTable(
            section.label,
            columns: const ['How', 'Share', 'Amount'],
            rows: [
              for (final MapEntry(:key, :value) in report.byWay.entries)
                [methodLabel(key), _share(value, total), value],
            ],
            total: ['Total sales', total > 0 ? '100%' : null, total],
          ),
        );
      case ReportSection.customers when detail == ReportDetail.totals:
        final owing = report.customers;
        blocks.add(
          ReportTable(
            section.label,
            columns: const ['', 'Over two weeks', 'Owed'],
            rows: [
              [
                owing.length == 1 ? '1 customer' : '${owing.length} customers',
                owing.fold<int>(0, (sum, c) => sum + c.overTwoWeeksMinor),
                owing.fold<int>(0, (sum, c) => sum + c.owedMinor),
              ],
            ],
            note: asOfToday,
          ),
        );
      case ReportSection.customers:
        blocks.add(
          ReportTable(
            section.label,
            columns: const ['Customer', 'Over two weeks', 'Owed'],
            rows: [
              for (final c in report.customers)
                [
                  c.name,
                  c.overTwoWeeksMinor > 0 ? c.overTwoWeeksMinor : null,
                  c.owedMinor,
                ],
            ],
            total: [
              'Total',
              null,
              report.customers.fold<int>(0, (sum, c) => sum + c.owedMinor),
            ],
            note: asOfToday,
          ),
        );
      case ReportSection.suppliers when detail == ReportDetail.totals:
        final owed = [
          for (final s in report.suppliers)
            if (s.owedMinor > 0) s,
        ];
        blocks.add(
          ReportTable(
            section.label,
            columns: const ['', 'Owed'],
            rows: [
              [
                owed.length == 1 ? '1 supplier' : '${owed.length} suppliers',
                owed.fold<int>(0, (sum, s) => sum + s.owedMinor),
              ],
            ],
            note: asOfToday,
          ),
        );
      case ReportSection.suppliers:
        final owed = [
          for (final s in report.suppliers)
            if (s.owedMinor > 0) s,
        ];
        blocks.add(
          ReportTable(
            section.label,
            columns: const ['Supplier', 'Due', 'Owed'],
            rows: [
              for (final s in owed)
                [
                  s.name,
                  if (s.nextDue case final due?) _day(due) else null,
                  s.owedMinor,
                ],
            ],
            total: [
              'Total',
              null,
              owed.fold<int>(0, (sum, s) => sum + s.owedMinor),
            ],
            note: asOfToday,
          ),
        );
      case ReportSection.balance:
        final b = report.balance;
        blocks.add(
          ReportTable(
            '${section.label} on ${_day(period.lastDay)}',
            columns: const ['', 'Amount'],
            rows: [
              ['Cash, M-Pesa and bank', b.moneyMinor],
              ['Customers owe you', b.owedToYouMinor],
              if (b.stockMinor != 0) ['Stock', b.stockMinor],
              ['You owe suppliers', -b.owedToSuppliersMinor],
            ],
            total: ['What the business is worth', b.netMinor],
            note: b.paidYourselfMinor > 0
                ? 'Paid yourself in this period, moved to Personal: '
                      '${_plain(b.paidYourselfMinor)}.'
                : null,
          ),
        );
      case ReportSection.bestSellers:
        blocks.add(
          ReportTable(
            section.label,
            columns: const ['Item', 'Sold', 'Profit', 'Sales'],
            rows: [
              for (final s in report.bestSellers)
                [
                  s.service ? '${s.name} (service)' : s.name,
                  _quantity(s.quantityMilli, s.unit),
                  s.service ? null : s.profitMinor,
                  s.amountMinor,
                ],
            ],
          ),
        );
      case ReportSection.stock:
        final products = [
          for (final i in report.items)
            if (i.isProduct) i,
        ];
        blocks.add(
          ReportTable(
            section.label,
            columns: const ['Item', 'In stock', 'Average cost', 'Value'],
            rows: [
              for (final i in products)
                [
                  i.name,
                  _quantity(i.stockMilli, i.unit),
                  i.averageCostMinor,
                  i.valueMinor,
                ],
            ],
            total: [
              'Total',
              null,
              null,
              products.fold<int>(0, (sum, i) => sum + i.valueMinor),
            ],
            note: asOfToday,
          ),
        );
      case ReportSection.cashBook when detail == ReportDetail.totals:
        final days = (cashBook?.days ?? const <CashBookDay>[]).reversed;
        blocks.add(
          ReportTable(
            'Cash book by day',
            columns: const ['Date', 'In', 'Out'],
            rows: [
              for (final d in days) [d.date, d.inMinor, d.outMinor],
            ],
            total: [
              'Total',
              days.fold<int>(0, (sum, d) => sum + d.inMinor),
              days.fold<int>(0, (sum, d) => sum + d.outMinor),
            ],
          ),
        );
      case ReportSection.cashBook:
        final rows = <List<Object?>>[];
        var inTotal = 0;
        var outTotal = 0;
        for (final day in (cashBook?.days ?? const <CashBookDay>[]).reversed) {
          for (final line in day.lines.reversed) {
            final row = _cashRow(day.date, line, accountNames, categoryNames);
            if (row == null) continue;
            rows.add(row);
            inTotal += (row[3] as int?) ?? 0;
            outTotal += (row[4] as int?) ?? 0;
          }
        }
        blocks.add(
          ReportTable(
            'Cash book',
            columns: const ['Date', 'What', 'Account', 'In', 'Out'],
            rows: rows,
            total: ['', 'Total', '', inTotal, outTotal],
            note:
                'Moves between the business\'s own accounts show once and '
                'count neither in nor out.',
          ),
        );
      case ReportSection.tax:
        if (tax != null) blocks.add(_taxTable(tax, section.label));
      case ReportSection.insights:
        if (report.insights.isNotEmpty) {
          blocks.add(ReportNotes(section.label, report.insights));
        }
    }
  }
  return ReportDocument(
    title: title,
    business: business,
    coverLine: coverLine,
    period: period,
    made: today,
    currency: BaseCurrency.code,
    blocks: blocks,
    logo: logo,
  );
}

List<Object?>? _cashRow(
  CalendarDate date,
  ActivityLine line,
  Map<int, String> accounts,
  Map<int, String> categories,
) {
  String account(int id) => accounts[id] ?? 'Account';
  final day = date;
  switch (line) {
    case EntryLine(:final entry):
      final what = cashBookTitle(
        entry,
        categoryName: categories[entry.categoryId],
      );
      final fee = entry.feeMinor;
      return [
        day,
        what,
        account(entry.accountId),
        entry.isInflow ? entry.amountMinor : null,
        entry.isInflow ? (fee > 0 ? fee : null) : entry.amountMinor + fee,
      ];
    case OwnTransferLine(:final outflow, :final inflow, :final shown):
      final to = inflow == null ? 'another account' : account(inflow.accountId);
      final from = outflow == null
          ? 'another account'
          : account(outflow.accountId);
      final fee = outflow?.feeMinor ?? 0;
      return [
        day,
        'Moved from $from to $to',
        account(shown.accountId),
        null,
        fee > 0 ? fee : null,
      ];
    case DailyNoiseLine() && final noise:
      final inflow = noise.direction == TransactionDirection.inflow;
      return [
        day,
        noiseTitle(noise.group),
        account(noise.accountId),
        inflow ? noise.totalMinor : null,
        inflow ? null : noise.totalMinor,
      ];
  }
}

ReportTable _taxTable(TaxView view, String title) {
  final note =
      'An estimate from the tax pack, rules as of '
      '${_day(view.pack.rulesAsOf)}. Check with KRA or a tax adviser before '
      'you file.';
  switch (view.kind) {
    case TaxKind.incomeTax:
      final e = view.income;
      final f = e.figures;
      return ReportTable(
        '$title, ${e.year} to date',
        columns: const ['', 'Amount'],
        rows: [
          [view.services ? 'Fees earned' : 'Sales', f.incomeMinor],
          ['Costs', -f.costsMinor],
          ['Profit', f.profitMinor],
          [
            e.company
                ? 'Income tax on profit, company rate'
                : 'Income tax on profit, individual rates',
            e.taxMinor,
          ],
          ['Withheld by clients', -f.withheldMinor],
          ['Paid to KRA', -f.paidToKraMinor],
        ],
        total: ['Left to pay', e.leftMinor],
        note: note,
      );
    case TaxKind.turnover:
      final last = view.lastMonth;
      final now = view.thisMonth;
      final rate = rateText(view.pack.turnoverRate);
      return ReportTable(
        '$title: Turnover Tax at $rate',
        columns: const ['', 'Due', 'Amount'],
        rows: [
          ['Sales, ${_month(last.month)}', null, last.salesMinor],
          [
            'Turnover Tax, ${_month(last.month)}',
            _day(last.due),
            last.taxMinor,
          ],
          ['Paid to KRA', null, -last.paidMinor],
          ['Sales, ${_month(now.month)} so far', null, now.salesMinor],
          ['Turnover Tax so far', _day(now.due), now.taxMinor],
        ],
        total: ['May owe', null, view.owedMinor],
        note: note,
      );
    case TaxKind.belowTurnover:
      return ReportTable(
        title,
        columns: const ['', 'Amount'],
        rows: [
          ['Sales over the last 12 months', view.yearSalesMinor],
          ['Turnover Tax starts at', view.pack.turnoverFromMinor],
        ],
        note: note,
      );
  }
}

String _month(YearMonth m) => '${monthName(m)} ${m.year}';

String _plain(int minor) => formatMoney(Money(minor), withCurrency: false);

String _share(int value, int total) =>
    total <= 0 ? '' : '${(value * 100 / total).round()}%';

String _quantity(int milliQ, String? unit) {
  final q = quantityText(milliQ);
  return unit == null ? q : '$q ${unitFor(unit, milliQ)}';
}

String _day(CalendarDate d) => periodText(ReportPeriod(d, d.addDays(1), ''));

/// [doc] as CSV for a spreadsheet: each part's title, its columns, its rows
/// and total, with a blank line between parts. Money is in
/// [ReportDocument.currency] with two decimals and no separators.
String reportCsv(ReportDocument doc) {
  final out = StringBuffer();
  void row(List<Object?> cells) {
    out
      ..write(cells.map(_csvCell).join(','))
      ..write('\r\n');
  }

  row([doc.title]);
  row([doc.coverLine]);
  row([doc.periodLine]);
  row(['Amounts in ${doc.currency}']);
  for (final block in doc.blocks) {
    row(const []);
    row([block.title]);
    switch (block) {
      case ReportTable():
        row([
          for (final (i, c) in block.columns.indexed)
            i == 0 && c.isEmpty ? 'Item' : c,
        ]);
        for (final r in block.rows) {
          row(r);
        }
        if (block.total case final total?) row(total);
        if (block.note case final note?) row([note]);
      case ReportNotes():
        for (final l in block.lines) {
          row([l]);
        }
    }
  }
  return out.toString();
}

String _csvCell(Object? cell) {
  final text = switch (cell) {
    null => '',
    final int minor => _decimal(minor),
    final CalendarDate d => '$d',
    _ => '$cell',
  };
  final risky = RegExp(r'^[=+\-@\t\r]');
  final safe = cell is! int && risky.hasMatch(text) ? "'$text" : text;
  return safe.contains(RegExp('[",\r\n]'))
      ? '"${safe.replaceAll('"', '""')}"'
      : safe;
}

String _decimal(int minor) {
  final sign = minor < 0 ? '-' : '';
  final abs = minor.abs();
  return '$sign${abs ~/ 100}.${(abs % 100).toString().padLeft(2, '0')}';
}
