import '../documents/receipt.dart';
import '../enums.dart';
import 'slip.dart';

/// [r] for the counter printer, line by line like the PDF receipt.
Slip receiptSlip(
  Receipt r, {
  required String Function(SalePaymentMethod) label,
  required String Function(int minor) plain,
  required String date,
  required String time,
}) {
  final owed = r.owedMinor;
  return Slip([
    SlipCentre(r.business, bold: true, large: true),
    if (r.place case final place? when place.isNotEmpty) SlipCentre(place),
    if (r.phone case final phone? when phone.isNotEmpty) SlipCentre(phone),
    if (r.kraPin case final pin? when pin.isNotEmpty)
      SlipCentre('KRA PIN $pin'),
    const SlipRule(),
    SlipPair('Receipt', r.number),
    SlipPair(date, time),
    if (r.customer case final who?) SlipPair('Customer', who),
    const SlipRule(),
    for (final l in r.lines) SlipPair(l.label(plain), plain(l.totalMinor)),
    const SlipRule(),
    SlipPair('TOTAL', '${r.currency} ${plain(r.totalMinor)}', bold: true),
    for (final p in r.payments)
      if (p.method != SalePaymentMethod.credit) ...[
        SlipPair(label(p.method), plain(p.amountMinor)),
        if (p.code case final code?) SlipCentre(code),
      ],
    if (owed > 0) SlipPair('To pay', plain(owed), bold: true),
    if (r.payTo case final till? when till.isNotEmpty)
      SlipCentre('Pay to $till'),
    const SlipRule(),
    if (r.footer case final f? when f.isNotEmpty) SlipCentre(f),
    const SlipCentre('This is not an eTIMS tax invoice.'),
  ]);
}

/// The day's summary from Close the day: sales by how they were paid, and
/// the drawer.
Slip daySummarySlip({
  required String business,
  required String date,
  required int salesMinor,
  required Map<SalePaymentMethod, int> salesByWay,
  required int startMinor,
  required int inMinor,
  required int outMinor,
  required int expectedMinor,
  required int? countedMinor,
  required String printedAt,
  required String Function(SalePaymentMethod) label,
  required String Function(int minor) plain,
}) {
  final gap = countedMinor == null ? null : countedMinor - expectedMinor;
  return Slip([
    SlipCentre(business, bold: true, large: true),
    const SlipCentre('Day summary'),
    SlipCentre(date),
    const SlipRule(),
    SlipPair('Sales', plain(salesMinor), bold: true),
    for (final MapEntry(:key, :value) in salesByWay.entries)
      SlipPair('  ${label(key)}', plain(value)),
    const SlipRule(),
    SlipPair('Drawer at the start', plain(startMinor)),
    SlipPair('Cash in', plain(inMinor)),
    SlipPair('Cash out', plain(outMinor)),
    SlipPair('Should be in the drawer', plain(expectedMinor), bold: true),
    if (countedMinor != null) ...[
      SlipPair('Counted', plain(countedMinor), bold: true),
      SlipCentre(
        gap == 0
            ? 'It matches'
            : '${plain(gap!.abs())} ${gap > 0 ? 'more' : 'less'} than the '
                  'records',
      ),
    ],
    const SlipRule(),
    SlipCentre('Printed $printedAt'),
  ]);
}

/// A tab's bill before it is paid: each line and the total.
Slip billSlip({
  required String business,
  required String tab,
  required String date,
  required String time,
  required List<(String, int)> lines,
  required String currency,
  required String Function(int minor) plain,
}) => Slip([
  SlipCentre(business, bold: true, large: true),
  SlipCentre('Bill · $tab'),
  SlipPair(date, time),
  const SlipRule(),
  for (final (label, amount) in lines) SlipPair(label, plain(amount)),
  const SlipRule(),
  SlipPair(
    'TOTAL',
    '$currency ${plain(lines.fold(0, (sum, l) => sum + l.$2))}',
    bold: true,
  ),
  const SlipRule(),
  const SlipCentre('Your receipt comes when you pay.'),
]);
