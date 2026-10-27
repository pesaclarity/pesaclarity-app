import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/auth/domain/email_address.dart';

void main() {
  test('trims and lower-cases an address', () {
    expect(normaliseEmail('  Wanjiru@Example.COM '), 'wanjiru@example.com');
    expect(
      normaliseEmail('w.kamau+pesa@mail.example.co.ke'),
      'w.kamau+pesa@mail.example.co.ke',
    );
  });

  test('rejects what is not shaped like an address', () {
    for (final input in [
      '',
      'wanjiru',
      'wanjiru@',
      '@example.com',
      'wanjiru@example',
      'wanjiru@example.c',
      'wanjiru@.com',
      'wanjiru@example..com',
      'wan jiru@example.com',
      'wanjiru@@example.com',
      'wanjiru@example.com.',
      '0700 000 000',
    ]) {
      expect(normaliseEmail(input), isNull, reason: input);
    }
  });

  test('rejects an address longer than email allows', () {
    expect(normaliseEmail('${'a' * 250}@example.com'), isNull);
  });
}
