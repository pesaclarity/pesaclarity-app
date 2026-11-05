import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/enums.dart';
import 'package:pesaclarity/src/domain/stock/stock.dart';

void main() {
  test('average cost takes in each restock', () {
    // 6 kg at 80, then 10 kg for 780: 16 kg at 78.75, rounded to 79.
    expect(
      newAverageCost(
        stockMilli: 6000,
        averageMinor: 8000,
        quantityMilli: 10000,
        paidMinor: 78000,
      ),
      7875,
    );
    // Stock below zero counts as none.
    expect(
      newAverageCost(
        stockMilli: -2000,
        averageMinor: 8000,
        quantityMilli: 4000,
        paidMinor: 30000,
      ),
      7500,
    );
  });

  test('quantities read and write as people say them', () {
    expect(quantityFrom('0.5'), 500);
    expect(quantityFrom('2'), 2000);
    expect(quantityFrom('1,000.25'), 1000250);
    expect(quantityFrom('0.1234'), isNull);
    expect(quantityFrom('abc'), isNull);
    expect(quantityText(6000), '6');
    expect(quantityText(500), '0.5');
    expect(quantityText(2250), '2.25');
    expect(quantityText(-500), '-0.5');
  });

  test('units read right for one and many', () {
    expect(unitFor('bunch', 38000), 'bunches');
    expect(unitFor('bunch', 1000), 'bunch');
    expect(unitFor('kg', 6000), 'kg');
    expect(unitFor('piece', 3000), 'pieces');
    const tomatoes = Item(
      id: 1,
      kind: ItemKind.product,
      name: 'Tomatoes',
      unit: 'kg',
      priceMinor: 12000,
      stockMilli: 6000,
      averageCostMinor: 8000,
      warnBelowMilli: 10000,
    );
    expect(stockText(tomatoes), '6 kg');
    expect(priceText(tomatoes, (m) => '${m ~/ 100}'), '120 / kg');
    expect(tomatoes.isLow, isTrue);
    expect(tomatoes.valueMinor, 48000);
    expect(tomatoes.profitPerUnitMinor, 4000);
    expect(daysLeft(tomatoes, soldMilliPerDay: 3000), 2);
    const avocado = Item(
      id: 2,
      kind: ItemKind.product,
      name: 'Avocado',
      priceMinor: 3000,
      stockMilli: 22000,
    );
    expect(stockText(avocado), '22 left');
    expect(priceText(avocado, (m) => '${m ~/ 100}'), '30 each');
  });
}
