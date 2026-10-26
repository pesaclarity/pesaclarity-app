import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/network/certificate_pins.dart';

import 'test_certificate.dart';

void main() {
  final a = otherPins[0];
  final b = otherPins[1];

  test('blank config means no pinning', () {
    expect(CertificatePins.parse('').isConfigured, isFalse);
    expect(CertificatePins.parse('  ').isConfigured, isFalse);
  });

  test('parses hosts with two or more pins, with or without sha256/', () {
    final pins = CertificatePins.parse(
      'API.example.org=sha256/$a,$b; fl.example.org=$a,$b,$testCertificatePin',
    );
    expect(pins.error, isNull);
    expect(pins.isConfigured, isTrue);
    expect(pins.hosts, containsAll(['api.example.org', 'fl.example.org']));
    expect(pins.forHost('api.example.org'), {a, b});
    expect(pins.forHost('FL.example.org'), hasLength(3));
    expect(pins.forHost('other.example.org'), isNull);
  });

  test('a host with one pin is rejected so rotation stays possible', () {
    final pins = CertificatePins.parse('api.example.org=$a');
    expect(pins.error, contains('at least 2'));
    expect(pins.isConfigured, isTrue);
    expect(pins.forHost('api.example.org'), isNull);
  });

  test('a repeated pin does not count twice', () {
    expect(CertificatePins.parse('api.example.org=$a,$a').error, isNotNull);
  });

  test('malformed input is an error, not silently unpinned', () {
    for (final raw in [
      'api.example.org',
      'api.example.org=not-base64!,$a',
      'api.example.org=${a.substring(4)},$b',
      'https://api.example.org=$a,$b',
    ]) {
      final pins = CertificatePins.parse(raw);
      expect(pins.isConfigured, isTrue, reason: raw);
      expect(pins.error, isNotNull, reason: raw);
    }
  });

  test('the build define is empty in tests', () {
    expect(CertificatePins.fromEnvironment().isConfigured, isFalse);
  });
}
