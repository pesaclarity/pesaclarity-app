import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/stock/measure.dart';

void main() {
  const tot = Measure(
    id: 1,
    itemId: 1,
    name: 'Tot, 25 ml',
    units: 30,
    bases: 1,
    priceMinor: 15000,
  );
  const double = Measure(
    id: 2,
    itemId: 1,
    name: 'Double, 50 ml',
    units: 15,
    bases: 1,
    priceMinor: 28000,
  );
  const crate = Measure(id: 3, itemId: 2, name: 'Crate', units: 1, bases: 24);

  test('thirty tots, one at a time, take exactly one bottle', () {
    var carry = 0;
    var taken = 0;
    for (var i = 0; i < 30; i++) {
      final t = tot.take(1000, carry: carry);
      taken += t.takeMilli;
      carry = t.carry;
    }
    expect(taken, 1000);
    expect(carry, 0);
  });

  test('a returned tot puts back what it took', () {
    final out = tot.take(1000);
    final back = tot.take(-1000, carry: out.carry);
    expect(out.takeMilli + back.takeMilli, 0);
    expect(back.carry, 0);
  });

  test('a crate holds 24 of the unit', () {
    expect(crate.isPack, isTrue);
    expect(tot.isPack, isFalse);
    expect(crate.baseMilli(3000), 72000);
    expect(crate.take(1000).takeMilli, 24000);
    expect(tot.word, 'tot');
  });

  test('stock reads in packs or in parts', () {
    expect(
      stockInMeasures(102000, unit: 'Bottle', measures: [crate]),
      '4 crates and 6 left',
    );
    expect(
      stockInMeasures(48000, unit: 'Bottle', measures: [crate]),
      '2 crates left',
    );
    expect(inPacks(102000, crate, unit: 'Bottle'), '4 crates and 6 bottles');
    expect(
      stockInMeasures(5400, unit: 'Bottle', measures: [double, tot]),
      '5 bottles and 12 tots',
    );
    expect(stockInMeasures(400, unit: 'Bottle', measures: [tot]), '12 tots');
    expect(stockInMeasures(5000, unit: 'Bottle', measures: [tot]), '5 bottles');
    // Within half a tot of a whole bottle reads as the bottle.
    expect(stockInMeasures(4990, unit: 'Bottle', measures: [tot]), '5 bottles');
    expect(stockInMeasures(5000, unit: 'Bottle', measures: const []), isNull);
    expect(stockInMeasures(12000, unit: 'Bottle', measures: [crate]), isNull);
  });
}
