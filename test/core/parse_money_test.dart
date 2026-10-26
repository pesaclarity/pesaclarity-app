import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/money/money_format.dart';

void main() {
  test('parseMoneyMinor reads typed amounts', () {
    expect(parseMoneyMinor('15,000'), 1500000);
    expect(parseMoneyMinor(' 1200.5 '), 120050);
    expect(parseMoneyMinor('99.99'), 9999);
    expect(parseMoneyMinor('500', currency: 'UGX'), 500);
  });

  test('parseMoneyMinor refuses what is not a positive amount', () {
    for (final input in ['', '0', '-5', '1.234', 'abc', '1.2.3']) {
      expect(parseMoneyMinor(input), isNull, reason: input);
    }
  });
}
