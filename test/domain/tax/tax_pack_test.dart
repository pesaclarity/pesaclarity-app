import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/tax/tax_estimate.dart';
import 'package:pesaclarity/src/domain/tax/tax_pack.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';

TaxPack loadPack() => TaxPack.fromJson(
  (jsonDecode(File('assets/tax/tax_pack.json').readAsStringSync()) as Map)
      .cast<String, Object?>(),
);

void main() {
  final pack = loadPack();
  String plain(int minor) => '${minor ~/ 100}';

  test('the pack in the app reads, with a date and its sources', () {
    expect(pack.version, 1);
    expect(pack.rulesAsOf.year, greaterThanOrEqualTo(2026));
    expect(pack.sources.keys, containsAll(['turnoverTax', 'incomeTax']));
    expect(rateText(pack.turnoverRate), '1.5%');
    expect(rateText(pack.withholdingRate), '5%');
    expect(rateText(pack.vatRate), '16%');
    expect(rateText(3250), '32.5%');
  });

  test('income tax for an individual uses the bands less relief', () {
    // 1,012,000 profit: 28,800 + 25,000 + 187,200, less 28,800 relief.
    expect(pack.incomeTax(101200000, company: false), 21220000);
    expect(pack.incomeTax(20000000, company: false), 0);
    expect(pack.incomeTax(101200000, company: true), 30360000);
    expect(pack.incomeTax(-500000, company: false), 0);
  });

  test('which tax applies', () {
    TaxKind kind(int sales, {bool services = false}) =>
        taxKindFor(pack: pack, yearSalesMinor: sales, services: services);
    expect(kind(50000000), TaxKind.belowTurnover);
    expect(kind(420000000), TaxKind.turnover);
    expect(kind(3000000000), TaxKind.incomeTax);
    expect(kind(420000000, services: true), TaxKind.incomeTax);
  });

  test('Turnover Tax for a month is due on the 20th of the next', () {
    final m = turnoverMonth(
      pack,
      month: YearMonth(2026, 12),
      salesMinor: 2450000,
      paidMinor: 10000,
    );
    expect(m.taxMinor, 36750);
    expect(m.leftMinor, 26750);
    expect(m.due, CalendarDate(2027, 1, 20));
  });

  test('instalments and what is left to pay', () {
    final e = incomeTaxEstimate(
      pack,
      figures: const TaxFigures(
        incomeMinor: 126000000,
        costsMinor: 24800000,
        paidToKraMinor: 10740000,
        withheldMinor: 6300000,
      ),
      settings: const TaxSettings(),
      today: CalendarDate(2026, 11, 30),
    );
    expect(e.taxMinor, 21220000);
    expect(e.leftMinor, 4180000);
    expect(e.nextInstalment, CalendarDate(2026, 12, 20));
  });

  test('warns before the VAT line', () {
    expect(
      thresholdWarning(
        pack,
        yearSalesMinor: 450000000,
        settings: const TaxSettings(),
        plain: plain,
      ),
      contains('registers for VAT'),
    );
    expect(
      thresholdWarning(
        pack,
        yearSalesMinor: 450000000,
        settings: const TaxSettings(vatRegistered: true),
        plain: plain,
      ),
      isNull,
    );
    expect(
      thresholdWarning(
        pack,
        yearSalesMinor: 100000000,
        settings: const TaxSettings(),
        plain: plain,
      ),
      isNull,
    );
  });

  test('knows a payment to KRA', () {
    expect(pack.isKra(paybill: '572572'), isTrue);
    expect(pack.isKra(name: 'KRA'), isTrue);
    expect(pack.isKra(name: 'Kenya Revenue Authority'), isTrue);
    expect(pack.isKra(name: 'Krazy Kitchen'), isFalse);
  });
}
