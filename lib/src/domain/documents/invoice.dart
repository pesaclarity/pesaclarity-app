import '../hours/hours.dart';
import '../tax/tax_pack.dart';
import '../time/calendar.dart';

/// How an invoice bills: the hours logged, or items typed in.
enum BillBy {
  hours('Logged hours'),
  items('Items');

  const BillBy(this.label);

  final String label;
}

/// How much of the hours an invoice shows.
enum HoursDetail {
  total('Total only'),
  project('By project'),
  day('Day by day');

  const HoursDetail(this.label);

  final String label;
}

/// Withholding tax on an invoice's fees.
enum Withholding {
  none('No withholding tax'),
  deducts('Client deducts it'),
  onTop('Client pays it on top');

  const Withholding(this.label);

  final String label;
}

enum InvoiceLineKind { fees, cost }

/// One line of an invoice.
class InvoiceLine {
  const InvoiceLine({
    required this.kind,
    required this.name,
    required this.amountMinor,
    this.detail,
    this.quantityMilli,
    this.unitMinor,
  });

  final InvoiceLineKind kind;
  final String name;

  /// Such as `44 h × 2,500` or `Discovery workshop 4 h`.
  final String? detail;
  final int amountMinor;
  final int? quantityMilli;
  final int? unitMinor;
}

/// What an invoice adds up to.
class InvoiceTotals {
  const InvoiceTotals({
    required this.feesMinor,
    required this.feesShownMinor,
    required this.costsMinor,
    required this.discountMinor,
    required this.vatMinor,
    required this.withheldMinor,
  });

  /// The fees as agreed.
  final int feesMinor;

  /// The fees on the invoice: grossed up when the client pays the tax on
  /// top.
  final int feesShownMinor;

  /// Costs passed on to the client; no withholding on these.
  final int costsMinor;
  final int discountMinor;
  final int vatMinor;

  /// What the client keeps back and pays to KRA.
  final int withheldMinor;

  /// What the invoice is for.
  int get totalMinor => feesShownMinor + costsMinor - discountMinor + vatMinor;

  /// What the client pays the business.
  int get toPayMinor => totalMinor - withheldMinor;
}

/// The totals for [feesMinor] of fees and [costsMinor] of costs. When the
/// client pays withholding on top, the fees are grossed up to whole
/// shillings so that after the tax the business still gets the fees.
InvoiceTotals invoiceTotals({
  required int feesMinor,
  required int costsMinor,
  required Withholding withholding,
  required BasisPoints withholdingRate,
  int discountMinor = 0,
  BasisPoints? vatRate,
}) {
  final shown = switch (withholding) {
    Withholding.onTop =>
      ((feesMinor * 10000 / (10000 - withholdingRate)) / 100).ceil() * 100,
    _ => feesMinor,
  };
  final withheld = switch (withholding) {
    Withholding.none => 0,
    Withholding.deducts => applyRate(feesMinor, withholdingRate),
    Withholding.onTop => shown - feesMinor,
  };
  final vat = vatRate == null
      ? 0
      : applyRate(shown + costsMinor - discountMinor, vatRate);
  return InvoiceTotals(
    feesMinor: feesMinor,
    feesShownMinor: shown,
    costsMinor: costsMinor,
    discountMinor: discountMinor,
    vatMinor: vat,
    withheldMinor: withheld,
  );
}

/// Where an invoice stands.
enum InvoiceStatus {
  unpaid('Unpaid'),
  partPaid('Part paid'),
  paid('Paid'),
  overdue('Overdue');

  const InvoiceStatus(this.label);

  final String label;
}

InvoiceStatus invoiceStatus({
  required int toPayMinor,
  required int paidMinor,
  required CalendarDate? dueOn,
  required CalendarDate today,
}) {
  if (paidMinor >= toPayMinor) return InvoiceStatus.paid;
  if (dueOn != null && dueOn.isBefore(today)) return InvoiceStatus.overdue;
  if (paidMinor > 0) return InvoiceStatus.partPaid;
  return InvoiceStatus.unpaid;
}

/// The hours' lines on an invoice, as [detail] shows them. [plain] formats
/// amounts for the details.
List<InvoiceLine> hoursLines(
  List<HourEntry> entries,
  HoursDetail detail, {
  required String Function(int minor) plain,
  required String Function(CalendarDate) dayName,
}) {
  final billed = [
    for (final e in entries)
      if (e.billable) e,
  ];
  switch (detail) {
    case HoursDetail.total:
    case HoursDetail.project:
      return [
        for (final p in byProject(billed))
          InvoiceLine(
            kind: InvoiceLineKind.fees,
            name: p.project ?? 'Hours',
            detail: detail == HoursDetail.total || p.rateMinor == null
                ? '${hoursText(p.minutes)} hours'
                : '${hoursText(p.minutes)} h × ${plain(p.rateMinor!)}',
            amountMinor: p.amountMinor,
            quantityMilli: p.minutes * 1000 ~/ 60,
            unitMinor: p.rateMinor,
          ),
      ];
    case HoursDetail.day:
      final days = <CalendarDate, List<HourEntry>>{};
      for (final e in billed) {
        days.putIfAbsent(e.day, () => []).add(e);
      }
      final sorted = days.keys.toList()..sort();
      return [
        for (final d in sorted)
          InvoiceLine(
            kind: InvoiceLineKind.fees,
            name: dayName(d),
            detail: [
              for (final e in days[d]!) '${e.what} ${hoursText(e.minutes)} h',
            ].join(' · '),
            amountMinor: days[d]!.fold(0, (sum, e) => sum + e.amountMinor),
            quantityMilli:
                days[d]!.fold(0, (sum, e) => sum + e.minutes) * 1000 ~/ 60,
          ),
      ];
  }
}
