import '../enums.dart';
import '../stock/stock.dart';

/// One line of a receipt: what was sold, how much, at what price.
class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.totalMinor,
    this.quantityMilli,
    this.unit,
  });

  final String name;
  final int totalMinor;
  final int? quantityMilli;
  final String? unit;

  /// `Sukuma 3 × 20`, `Tomatoes 1 kg`, or the name alone.
  String label(String Function(int minor) plain) {
    final q = quantityMilli;
    if (q == null || q <= 0) return name;
    final unit = this.unit;
    if (unit != null) return '$name ${quantityText(q)} ${unitFor(unit, q)}';
    if (q == milli) return name;
    final each = (totalMinor * milli / q).round();
    return '$name ${quantityText(q)} × ${plain(each)}';
  }
}

/// How part of the sale was paid, with the M-Pesa or bank code when the
/// payment message is matched.
class ReceiptPayment {
  const ReceiptPayment({
    required this.method,
    required this.amountMinor,
    this.code,
  });

  final SalePaymentMethod method;
  final int amountMinor;
  final String? code;
}

/// A receipt for one sale, made on the phone.
class Receipt {
  const Receipt({
    required this.number,
    required this.at,
    required this.business,
    required this.lines,
    required this.totalMinor,
    required this.payments,
    required this.currency,
    this.place,
    this.phone,
    this.payTo,
    this.kraPin,
    this.footer,
    this.customer,
    this.blackAndWhite = false,
  });

  final String number;
  final DateTime at;
  final String business;
  final String? place;
  final String? phone;

  /// Till or Paybill.
  final String? payTo;
  final String? kraPin;
  final List<ReceiptLine> lines;
  final int totalMinor;
  final List<ReceiptPayment> payments;
  final String currency;
  final String? footer;

  /// Who bought, when known.
  final String? customer;

  /// Printed without colour, for a thermal printer.
  final bool blackAndWhite;

  int get owedMinor => payments
      .where((p) => p.method == SalePaymentMethod.credit)
      .fold(0, (sum, p) => sum + p.amountMinor);

  int get paidMinor => totalMinor - owedMinor;

  /// The fileName for [extension]: `receipt-vs-000245.png`.
  String fileName(String extension) =>
      'receipt-${number.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-')}'
      '.$extension';
}

/// The line under the total: `PAID · M-Pesa SKL4H7X2QP`, or what is owed.
String receiptPaidLine(
  Receipt r,
  String Function(SalePaymentMethod) label,
  String Function(int minor) plain,
) {
  final paid = [
    for (final p in r.payments)
      if (p.method != SalePaymentMethod.credit)
        [label(p.method), ?p.code].join(' '),
  ];
  if (r.owedMinor == 0) return 'PAID · ${paid.join(' + ')}';
  if (paid.isEmpty) return 'TO PAY · ${plain(r.owedMinor)}';
  return 'PAID ${plain(r.paidMinor)} · ${paid.join(' + ')} · '
      'TO PAY ${plain(r.owedMinor)}';
}

/// The receipt as plain text for SMS.
String receiptText(
  Receipt r, {
  required String Function(SalePaymentMethod) label,
  required String Function(int minor) plain,
  required String when,
}) {
  final out = StringBuffer()
    ..writeln(r.business)
    ..writeln('Receipt ${r.number} · $when');
  for (final l in r.lines) {
    out.writeln('${l.label(plain)}: ${plain(l.totalMinor)}');
  }
  out
    ..writeln('Total: ${r.currency} ${plain(r.totalMinor)}')
    ..writeln(receiptPaidLine(r, label, plain));
  if (r.payTo case final till?) out.writeln('Pay to $till');
  if (r.footer case final f? when f.isNotEmpty) out.writeln(f);
  out.write('This is not an eTIMS tax invoice.');
  return out.toString();
}
