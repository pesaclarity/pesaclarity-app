import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The base64 SHA-256 of the SubjectPublicKeyInfo in a DER certificate.
///
/// Throws [FormatException] when [certificateDer] is not a certificate.
String spkiSha256(Uint8List certificateDer) {
  final spki = subjectPublicKeyInfo(certificateDer);
  return base64.encode(Sha256().toSync().hashSync(spki).bytes);
}

/// Extracts the encoded SubjectPublicKeyInfo from a DER X.509 certificate.
///
/// Certificate ::= SEQUENCE { tbsCertificate SEQUENCE { [0] version OPTIONAL,
/// serialNumber, signature, issuer, validity, subject,
/// subjectPublicKeyInfo, ... }, ... }
Uint8List subjectPublicKeyInfo(Uint8List certificateDer) {
  final certificate = _Tlv.read(certificateDer, 0);
  _expect(certificate.tag == 0x30, 'certificate');
  final tbs = _Tlv.read(certificateDer, certificate.valueStart);
  _expect(tbs.tag == 0x30, 'tbsCertificate');

  var offset = tbs.valueStart;
  var field = _Tlv.read(certificateDer, offset);
  if (field.tag == 0xa0) {
    offset = field.end;
    field = _Tlv.read(certificateDer, offset);
  }
  // serialNumber, signature, issuer, validity, subject.
  for (var i = 0; i < 5; i++) {
    _expect(field.end <= tbs.end, 'tbsCertificate fields');
    offset = field.end;
    field = _Tlv.read(certificateDer, offset);
  }
  _expect(field.tag == 0x30 && field.end <= tbs.end, 'subjectPublicKeyInfo');
  return Uint8List.sublistView(certificateDer, field.start, field.end);
}

void _expect(bool condition, String what) {
  if (!condition) throw FormatException('Malformed certificate: $what');
}

/// One DER tag-length-value header.
class _Tlv {
  const _Tlv(this.tag, this.start, this.valueStart, this.end);

  final int tag;
  final int start;
  final int valueStart;
  final int end;

  static _Tlv read(Uint8List bytes, int start) {
    _expect(start + 2 <= bytes.length, 'truncated');
    final tag = bytes[start];
    var offset = start + 1;
    var length = bytes[offset++];
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      _expect(count >= 1 && count <= 4, 'length');
      _expect(offset + count <= bytes.length, 'truncated');
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | bytes[offset++];
      }
    }
    final end = offset + length;
    _expect(end <= bytes.length, 'truncated');
    return _Tlv(tag, start, offset, end);
  }
}
