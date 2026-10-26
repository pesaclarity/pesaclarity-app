import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/security/application/balance_visibility.dart';
import 'package:pesaclarity/src/features/security/domain/lock_settings.dart';

void main() {
  test('masks every amount and keeps the words', () {
    expect(
      maskAmounts('KES 1,200 over today. Weekdays KES 950.50, weekends -KES 3'),
      'KES ••••• over today. Weekdays KES •••••, weekends KES •••••',
    );
    expect(maskAmounts('Debt-free by Mar 2028'), 'Debt-free by Mar 2028');
    expect(maskAmounts('KES —'), 'KES —');
  });

  test('finds amounts', () {
    expect(containsAmount('KES 1,200'), isTrue);
    expect(containsAmount('Score 72'), isFalse);
    expect(maskAmountsIf(false, 'KES 5'), 'KES 5');
  });

  test('labels lock-after choices', () {
    expect(LockSettings.lockAfterChoices.map(lockAfterLabel), [
      'Immediately',
      '30 seconds',
      '1 minute',
      '5 minutes',
    ]);
  });
}
