import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/backup/backup.dart';

void main() {
  // Computed independently with Python (Crockford base32, SHA-256 checksum).
  const knownDisplay =
      '000G-40R4-0M30-E209-185G-R38E-1W81-24GK-2GAH-C5RR-34D1-P70X-3RFP-63ED';
  final knownBytes = List<int>.generate(32, (i) => i);

  test('encodes a known key to the expected grouped string', () {
    expect(RecoveryKey.fromBytes(knownBytes).toDisplayString(), knownDisplay);
  });

  test('parses the grouped string back to the same bytes', () {
    expect(RecoveryKey.parse(knownDisplay).bytes, knownBytes);
  });

  test('parsing ignores case, spaces, hyphens and look-alike letters', () {
    final sloppy = knownDisplay
        .toLowerCase()
        .replaceAll('-', ' ')
        .replaceAll('0', 'o')
        .replaceAll('1', 'l');
    expect(RecoveryKey.parse(sloppy), RecoveryKey.fromBytes(knownBytes));
  });

  test('round trips random keys', () {
    final random = Random(7);
    for (var i = 0; i < 50; i++) {
      final key = RecoveryKey.generate(random);
      final display = key.toDisplayString();
      expect(display, matches(RegExp(r'^([0-9A-Z]{4}-){13}[0-9A-Z]{4}$')));
      expect(RecoveryKey.parse(display), key);
    }
  });

  test('a single typo fails the checksum', () {
    final typo = knownDisplay.replaceFirst('R4', 'R5');
    expect(
      () => RecoveryKey.parse(typo),
      throwsA(isA<InvalidRecoveryKeyException>()),
    );
  });

  test('wrong length and unknown characters are rejected', () {
    expect(
      () => RecoveryKey.parse(knownDisplay.substring(5)),
      throwsA(isA<InvalidRecoveryKeyException>()),
    );
    expect(
      () => RecoveryKey.parse(knownDisplay.replaceFirst('G', 'U')),
      throwsA(isA<InvalidRecoveryKeyException>()),
    );
  });

  test('toString never reveals the key', () {
    expect(
      RecoveryKey.fromBytes(knownBytes).toString(),
      isNot(contains('000G')),
    );
  });
}
