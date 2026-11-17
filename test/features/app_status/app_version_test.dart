import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/app_status/domain/app_version.dart';

AppVersion v(String text) => AppVersion.tryParse(text)!;

void main() {
  test('orders versions the SemVer way', () {
    const ordered = [
      '0.2.9',
      '0.3.0-alpha',
      '0.3.0-alpha.1',
      '0.3.0-dev.2',
      '0.3.0-dev.10',
      '0.3.0',
      '0.3.2',
      '0.4.0',
      '0.10.0',
      '1.0.0',
    ];
    for (var i = 0; i < ordered.length - 1; i++) {
      expect(v(ordered[i]) < v(ordered[i + 1]), isTrue, reason: ordered[i]);
      expect(v(ordered[i + 1]) > v(ordered[i]), isTrue, reason: ordered[i]);
    }
  });

  test('ignores build metadata', () {
    expect(v('0.3.0+7'), v('0.3.0'));
    expect(v('0.3.0+7').compareTo(v('0.3.0+8')), 0);
  });

  test('refuses what is not a version', () {
    for (final text in [
      '',
      '0.3',
      '0.3.0.1',
      'v0.3.0',
      '01.2.3',
      'x',
      '1.' * 40,
    ]) {
      expect(AppVersion.tryParse(text), isNull, reason: text);
    }
  });

  test('prints itself', () {
    expect(v('0.4.0-dev.31').toString(), '0.4.0-dev.31');
  });
}
