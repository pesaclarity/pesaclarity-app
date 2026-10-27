import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/core/network/pinned_http_client.dart';
import 'package:pesaclarity/src/core/network/trusted_roots.dart';

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

TrustedRoots roots(String hosts, List<String> rootsDer) =>
    TrustedRoots.parse(hosts: hosts, roots: rootsDer.join(','));

void main() {
  late FakeServer server;

  setUp(() async => server = await FakeServer.start());
  tearDown(() => server.close());

  HttpClientFactory factory(TrustedRoots roots) =>
      HttpClientFactory(roots, context: clientContext());

  test('connects when the chain ends in a trusted root', () async {
    final pinned = factory(roots('127.0.0.1', [otherRootsDer[0], testRootDer]));
    expect(pinned.pinning, isTrue);
    expect(await get(pinned.create(), server.url('/v1/ping')), 200);
    expect(server.requests, ['/v1/ping']);
  });

  test('refuses a chain from another authority before sending', () async {
    final pinned = factory(roots('127.0.0.1', otherRootsDer));
    await expectLater(
      get(pinned.create(), server.url('/v1/secret')),
      throwsA(isA<HandshakeException>()),
    );
    expect(server.requests, isEmpty);
  });

  test('ignores the platform roots once pinning is on', () async {
    // clientContext() trusts the test root, but the pins do not.
    final pinned = factory(roots('127.0.0.1', otherRootsDer));
    expect(pinned.context, isNotNull);
    await expectLater(
      get(pinned.create(), server.url('/')),
      throwsA(isA<HandshakeException>()),
    );
  });

  test('refuses hosts that are not pinned once pinning is on', () async {
    final pinned = factory(
      roots('api.example.org', [testRootDer, ...otherRootsDer]),
    );
    await expectLater(
      get(pinned.create(), server.url('/')),
      throwsA(isA<CertificatePinningException>()),
    );
    expect(server.requests, isEmpty);
  });

  test('an invalid config fails closed', () async {
    final pinned = factory(roots('127.0.0.1', [testRootDer]));
    expect(pinned.roots.error, isNotNull);
    await expectLater(
      get(pinned.create(), server.url('/')),
      throwsA(isA<CertificatePinningException>()),
    );
    expect(server.requests, isEmpty);
  });

  test('refuses plain http once pinning is on', () async {
    final pinned = factory(roots('127.0.0.1', [testRootDer, ...otherRootsDer]));
    await expectLater(
      get(pinned.create(), Uri.parse('http://127.0.0.1:9/')),
      throwsA(isA<CertificatePinningException>()),
    );
  });

  test('without pinning it uses the normal certificate checks only', () async {
    final unpinned = factory(TrustedRoots.none);
    expect(unpinned.pinning, isFalse);
    expect(await get(unpinned.create(), server.url('/')), 200);
  });

  test('createUnpinned ignores pinning, for third-party services', () async {
    final pinned = factory(roots('api.example.org', otherRootsDer));
    expect(await get(pinned.createUnpinned(), server.url('/')), 200);
  });

  group('TrustedRoots.parse', () {
    test('blank config means no pinning', () {
      final none = TrustedRoots.parse(hosts: ' ', roots: '');
      expect(none.isConfigured, isFalse);
      expect(none.error, isNull);
    });

    test('reads hosts and roots, ignoring case, spaces and repeats', () {
      final parsed = TrustedRoots.parse(
        hosts: 'API.example.org, vault.example.org,',
        roots: ' $testRootDer , ${otherRootsDer[0]},$testRootDer',
      );
      expect(parsed.error, isNull);
      expect(parsed.hosts, {'api.example.org', 'vault.example.org'});
      expect(parsed.isPinned('Vault.Example.org'), isTrue);
      expect(parsed.isPinned('other.example.org'), isFalse);
    });

    test('a mistake is an error, never silently unpinned', () {
      final cases = {
        'one root': roots('api.example.org', [testRootDer]),
        'one root repeated': roots('api.example.org', [
          testRootDer,
          testRootDer,
        ]),
        'roots without hosts': roots('', [testRootDer, ...otherRootsDer]),
        'hosts without roots': roots('api.example.org', []),
        'host with a scheme': roots('https://api.example.org', otherRootsDer),
        'not base64': TrustedRoots.parse(
          hosts: 'api.example.org',
          roots: 'not base64!,$testRootDer',
        ),
        'not a certificate': roots('api.example.org', [
          base64.encode(List.filled(64, 7)),
          testRootDer,
        ]),
      };
      for (final MapEntry(:key, :value) in cases.entries) {
        expect(value.error, isNotNull, reason: key);
        expect(value.isConfigured, isTrue, reason: key);
        expect(value.isPinned('api.example.org'), isFalse, reason: key);
      }
    });
  });
}
