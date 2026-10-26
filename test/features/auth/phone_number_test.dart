import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/auth/data/device_name.dart';
import 'package:pesaclarity/src/features/auth/domain/phone_number.dart';
import 'package:pesaclarity/src/features/auth/presentation/account_section.dart';

void main() {
  group('normaliseKenyanMobile', () {
    test('accepts the usual ways of typing a number', () {
      for (final input in [
        '0700 000 000',
        '700000000',
        '254700000000',
        '+254 700 000 000',
        '0700-000-000',
      ]) {
        expect(normaliseKenyanMobile(input), '+254700000000', reason: input);
      }
      expect(normaliseKenyanMobile('0110 000 000'), '+254110000000');
    });

    test('rejects numbers that are not Kenyan mobiles', () {
      for (final input in ['', '0700', '0200 000 000', '+1 415 555 0100']) {
        expect(normaliseKenyanMobile(input), isNull, reason: input);
      }
    });
  });

  test('formats a number for display', () {
    expect(formatKenyanMobile('+254700000000'), '+254 700 000 000');
    expect(formatKenyanMobile('+1415'), '+1415');
  });

  test('cleans device names to the server limit', () {
    expect(cleanDeviceName('  Tecno   Spark 20 '), 'Tecno Spark 20');
    expect(cleanDeviceName(null), PlatformDeviceNameSource.fallback);
    expect(cleanDeviceName('x' * 80), hasLength(64));
  });

  test('takes initials from a display name', () {
    expect(initialsOf('John Kamau'), 'JK');
    expect(initialsOf('john'), 'J');
    expect(initialsOf('  '), isNull);
    expect(initialsOf(null), isNull);
  });
}
