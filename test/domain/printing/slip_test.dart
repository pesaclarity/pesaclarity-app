import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/documents/receipt.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/printing/slip.dart';
import 'package:pesaclarity/src/domain/printing/slips.dart';

/// Receipts and day summaries on a counter printer (synthetic data).
void main() {
  String plain(int minor) => '${minor ~/ 100}';
  String label(SalePaymentMethod m) => switch (m) {
    SalePaymentMethod.cash => 'Cash',
    SalePaymentMethod.mpesa => 'M-Pesa',
    SalePaymentMethod.bank => 'Bank',
    SalePaymentMethod.credit => 'On credit',
  };

  test('lays lines out across the paper', () {
    const slip = Slip([
      SlipCentre('Shop'),
      SlipRule(),
      SlipPair('Tomatoes 1 kg', '120'),
      SlipPair('A very long item name that needs two lines', '60'),
    ]);
    final lines = slip.render(32);
    expect(lines[0], '              Shop');
    expect(lines[1], '-' * 32);
    expect(lines[2], 'Tomatoes 1 kg${' ' * 16}120');
    expect(lines[2].length, 32);
    expect(lines.sublist(3), [
      'A very long item name that needs',
      'two lines${' ' * 21}60',
    ]);
    expect(Slip.columnsFor(58), 32);
    expect(Slip.columnsFor(80), 48);
  });

  test('writes ESC/POS: reset, text, feed and cut', () {
    final bytes = const Slip([SlipCentre('Shop', bold: true)]).escPos(58);
    expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    expect(latin1.decode(bytes, allowInvalid: true), contains('Shop'));
    expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 66, 0]);
  });

  test('keeps to characters every printer has', () {
    expect(
      printable('Kale 3 × 20 · M-Pesa – ok ✓'),
      'Kale 3 x 20 - M-Pesa - ok ?',
    );
  });

  test('a receipt prints like the PDF one', () {
    final r = Receipt(
      number: 'VS-000245',
      at: DateTime.utc(2026, 11, 10, 11, 41),
      business: 'Green Basket Grocers',
      place: 'Main Market, stall 12',
      phone: '0700 000 000',
      lines: const [
        ReceiptLine(name: 'Kale', totalMinor: 6000, quantityMilli: 3000),
        ReceiptLine(name: 'Tomatoes', totalMinor: 12000),
      ],
      totalMinor: 18000,
      payments: const [
        ReceiptPayment(
          method: SalePaymentMethod.mpesa,
          amountMinor: 18000,
          code: 'TK10000001',
        ),
      ],
      currency: 'KES',
      footer: 'Thank you, see you again!',
    );
    final text = receiptSlip(
      r,
      label: label,
      plain: plain,
      date: '10 Nov 2026',
      time: '2:41 pm',
    ).render(32).join(' ').replaceAll(RegExp(r'\s+'), ' ');
    expect(text, contains('Green Basket Grocers'));
    expect(text, contains('VS-000245'));
    expect(text, contains('Kale 3 x 20'));
    expect(text, contains('KES 180'));
    expect(text, contains('TK10000001'));
    expect(text, contains('Thank you, see you again!'));
    expect(text, contains('This is not an eTIMS tax invoice.'));
  });

  test("the day's summary says whether the drawer matches", () {
    Slip day(int? counted) => daySummarySlip(
      business: 'Green Basket Grocers',
      date: 'Tuesday 10 November',
      salesMinor: 396000,
      salesByWay: const {
        SalePaymentMethod.cash: 169000,
        SalePaymentMethod.mpesa: 183000,
        SalePaymentMethod.credit: 44000,
      },
      startMinor: 50000,
      inMinor: 169000,
      outMinor: 50000,
      expectedMinor: 169000,
      countedMinor: counted,
      printedAt: '9:12 pm',
      label: label,
      plain: plain,
    );
    String flat(Slip s) =>
        s.render(32).join(' ').replaceAll(RegExp(r'\s+'), ' ');
    final matches = flat(day(169000));
    expect(matches, contains('Sales'));
    expect(matches, contains('M-Pesa'));
    expect(matches, contains('It matches'));
    expect(flat(day(164000)), contains('50 less than the records'));
    expect(flat(day(null)), isNot(contains('Counted')));
  });
}
