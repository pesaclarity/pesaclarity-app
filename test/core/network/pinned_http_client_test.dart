import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/network/certificate_pins.dart';
import 'package:pesaclarity/src/core/network/pinned_http_client.dart';

import 'test_certificate.dart';

/// A local https server standing in for the Pesa Clarity API.
class FakeServer {
  FakeServer._(this._server);

  final HttpServer _server;
  final requests = <String>[];

  static Future<FakeServer> start() async {
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverContext(),
    );
    final fake = FakeServer._(server);
    server.listen((request) async {
      fake.requests.add(request.uri.path);
      request.response.write('ok');
      await request.response.close();
    }, onError: (_) {});
    return fake;
  }

  Uri url(String path) => Uri.parse('https://127.0.0.1:${_server.port}$path');

  Future<void> close() => _server.close(force: true);
}

Future<int> get(HttpClient client, Uri url) async {
  try {
    final response = await (await client.getUrl(url)).close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  late FakeServer server;

  setUp(() async => server = await FakeServer.start());
  tearDown(() => server.close());

  HttpClientFactory factory(CertificatePins pins) =>
      HttpClientFactory(pins, context: clientContext());

  test('connects when the server key matches one of the pins', () async {
    final pins = CertificatePins.of({
      '127.0.0.1': [otherPins[0], testCertificatePin],
    });
    expect(await get(factory(pins).create(), server.url('/v1/ping')), 200);
    expect(server.requests, ['/v1/ping']);
  });

  test(
    'refuses a key that matches no pin before sending the request',
    () async {
      final pins = CertificatePins.of({'127.0.0.1': otherPins});
      await expectLater(
        get(factory(pins).create(), server.url('/v1/secret')),
        throwsA(isA<CertificatePinningException>()),
      );
      expect(server.requests, isEmpty);
    },
  );

  test('refuses hosts without pins once pinning is on', () async {
    final pins = CertificatePins.of({'api.example.org': otherPins});
    await expectLater(
      get(factory(pins).create(), server.url('/')),
      throwsA(isA<CertificatePinningException>()),
    );
    expect(server.requests, isEmpty);
  });

  test('an invalid pin config fails closed', () async {
    final pins = CertificatePins.parse('127.0.0.1=$testCertificatePin');
    expect(pins.error, isNotNull);
    await expectLater(
      get(factory(pins).create(), server.url('/')),
      throwsA(isA<CertificatePinningException>()),
    );
    expect(server.requests, isEmpty);
  });

  test('refuses plain http once pinning is on', () async {
    final pins = CertificatePins.of({'127.0.0.1': otherPins});
    await expectLater(
      get(factory(pins).create(), Uri.parse('http://127.0.0.1:9/')),
      throwsA(isA<CertificatePinningException>()),
    );
  });

  test('without pins it uses the normal certificate checks only', () async {
    final unpinned = factory(CertificatePins.none);
    expect(unpinned.pinning, isFalse);
    expect(await get(unpinned.create(), server.url('/')), 200);
  });

  test('createUnpinned ignores the pins, for third-party services', () async {
    final pins = CertificatePins.of({'api.example.org': otherPins});
    expect(await get(factory(pins).createUnpinned(), server.url('/')), 200);
  });

  group('verifyPeerCertificate', () {
    final pins = CertificatePins.of({
      'api.example.org': [testCertificatePin, otherPins[0]],
    });

    test('accepts a pinned key', () {
      verifyPeerCertificate(pins, 'API.example.org', testCertificateDer);
    });

    test('refuses a missing, unreadable or unpinned certificate', () {
      final refused = throwsA(isA<CertificatePinningException>());
      expect(
        () => verifyPeerCertificate(pins, 'api.example.org', null),
        refused,
      );
      expect(
        () => verifyPeerCertificate(pins, 'api.example.org', Uint8List(4)),
        refused,
      );
      expect(
        () => verifyPeerCertificate(pins, 'fl.example.org', testCertificateDer),
        refused,
      );
      final rotated = CertificatePins.of({'api.example.org': otherPins});
      expect(
        () => verifyPeerCertificate(
          rotated,
          'api.example.org',
          testCertificateDer,
        ),
        refused,
      );
    });
  });
}
