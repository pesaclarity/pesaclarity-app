import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/network/spki.dart';

import 'test_certificate.dart';

void main() {
  test('hashes the SubjectPublicKeyInfo the same way openssl does', () {
    expect(spkiSha256(testCertificateDer), testCertificatePin);
  });

  test('extracts a P-256 SubjectPublicKeyInfo', () {
    // SEQUENCE of 89 bytes: algorithm identifiers plus a 65-byte point.
    final spki = subjectPublicKeyInfo(testCertificateDer);
    expect(spki.length, 91);
    expect(spki.first, 0x30);
  });

  test('rejects bytes that are not a certificate', () {
    expect(() => spkiSha256(Uint8List(0)), throwsFormatException);
    expect(
      () => spkiSha256(Uint8List.fromList([0x30, 0x03, 0x02, 0x01, 0x00])),
      throwsFormatException,
    );
    final truncated = Uint8List.sublistView(testCertificateDer, 0, 120);
    expect(() => spkiSha256(truncated), throwsFormatException);
  });
}
