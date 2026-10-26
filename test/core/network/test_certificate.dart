import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A self-signed P-256 certificate for `localhost` and 127.0.0.1, made for
/// these tests only. The key protects nothing.
const testCertificatePem = '''
-----BEGIN CERTIFICATE-----
MIIBnDCCAUGgAwIBAgIUNWONXHwrpEV13SQQxjCe6qchH8wwCgYIKoZIzj0EAwIw
FDESMBAGA1UEAwwJbG9jYWxob3N0MCAXDTI2MTAyNjE0NTgzMVoYDzIxMjYxMDAy
MTQ1ODMxWjAUMRIwEAYDVQQDDAlsb2NhbGhvc3QwWTATBgcqhkjOPQIBBggqhkjO
PQMBBwNCAAQjoYzRJLD6LMoUoRqPCSrEZaITjBzrTiM1I4qs8W5/Nm7pY7bVmL72
EwXiHSJff3XNGBFAsCmP9IYLw96FLYIvo28wbTAdBgNVHQ4EFgQU3kx+r2Fltq3b
ZXyax7mX3WIko1swHwYDVR0jBBgwFoAU3kx+r2Fltq3bZXyax7mX3WIko1swDwYD
VR0TAQH/BAUwAwEB/zAaBgNVHREEEzARgglsb2NhbGhvc3SHBH8AAAEwCgYIKoZI
zj0EAwIDSQAwRgIhAO00e6bHLT6zqOOYWiaH7upIkmTcbmiIM8RlS+WfgHGEAiEA
/MXzMVAh1Nl4aLeqYSrrPPOLpmuSI4+fRv3k2ixVgj8=
-----END CERTIFICATE-----
''';

const _testKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgb7ZrFQc0s+sTTj5w
mzO4CUhKoUtDEd/eFTHhUFZns/+hRANCAAQjoYzRJLD6LMoUoRqPCSrEZaITjBzr
TiM1I4qs8W5/Nm7pY7bVmL72EwXiHSJff3XNGBFAsCmP9IYLw96FLYIv
-----END PRIVATE KEY-----
''';

/// The certificate's SPKI SHA-256 pin, computed with
/// `openssl x509 -pubkey | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64`.
const testCertificatePin = '2uXRtU7UT6D8cPd3YTmySh9fKmyPUOoJHRmiv0CCXJE=';

/// Two well-formed pins that match nothing.
final otherPins = [
  base64.encode(List.filled(32, 1)),
  base64.encode(List.filled(32, 2)),
];

Uint8List get testCertificateDer {
  final body = testCertificatePem
      .split('\n')
      .where((line) => line.isNotEmpty && !line.startsWith('-----'))
      .join();
  return base64.decode(body);
}

SecurityContext serverContext() => SecurityContext()
  ..useCertificateChainBytes(utf8.encode(testCertificatePem))
  ..usePrivateKeyBytes(utf8.encode(_testKeyPem));

/// Trusts only the test certificate, standing in for the platform's roots.
SecurityContext clientContext() =>
    SecurityContext()
      ..setTrustedCertificatesBytes(utf8.encode(testCertificatePem));
