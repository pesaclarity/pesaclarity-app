import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pesaclarity/src/core/integrity/app_attest.dart';
import 'package:pesaclarity/src/core/integrity/integrity_attestor.dart';
import 'package:pesaclarity/src/features/security/data/secure_store.dart';

List<int> _sha256(List<int> data) => Sha256().toSync().hashSync(data).bytes;

class _FakeApple implements AppAttestService {
  bool supported = true;
  int keys = 0;
  PlatformException? assertionError;
  final attested = <(String, List<int>)>[];
  final asserted = <(String, List<int>)>[];

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<String> generateKey() async => 'key-${++keys}';

  @override
  Future<String> attestKey(String keyId, List<int> clientDataHash) async {
    attested.add((keyId, clientDataHash));
    return 'attestation-of-$keyId';
  }

  @override
  Future<String> generateAssertion(
    String keyId,
    List<int> clientDataHash,
  ) async {
    if (assertionError != null) throw assertionError!;
    asserted.add((keyId, clientDataHash));
    return 'assertion-${asserted.length}';
  }
}

class _FakeServer implements AppAttestServer {
  bool off = false;
  final registered = <(String, String, String)>[];

  @override
  Future<String> challenge() async {
    if (off) throw const AppAttestOff();
    return base64.encode(utf8.encode('challenge-${registered.length}'));
  }

  @override
  Future<void> registerKey({
    required String keyId,
    required String attestation,
    required String challenge,
  }) async => registered.add((keyId, attestation, challenge));
}

void main() {
  late _FakeApple apple;
  late _FakeServer server;
  late MemorySecureStore store;
  String? account;

  setUp(() {
    apple = _FakeApple();
    server = _FakeServer();
    store = MemorySecureStore();
    account = 'account-1';
  });

  AppAttestAttestor attestor() => AppAttestAttestor(
    service: apple,
    server: server,
    store: store,
    accountId: () async => account,
  );

  test('registers a key once, then signs each request hash', () async {
    final first = await attestor().attest(requestHash: 'hash-a');
    final second = await attestor().attest(requestHash: 'hash-b');

    expect((first as Attested).token, 'appattest key-1 assertion-1');
    expect((second as Attested).token, 'appattest key-1 assertion-2');
    expect(server.registered, [
      ('key-1', 'attestation-of-key-1', server.registered.single.$3),
    ]);
    // Apple attests over the SHA-256 of the raw challenge.
    final challenge = base64.decode(server.registered.single.$3);
    expect(apple.attested.single.$2, _sha256(challenge));
    // Assertions sign the SHA-256 of the request hash text, as the server
    // checks them.
    expect(apple.asserted.first.$2, _sha256(utf8.encode('hash-a')));
  });

  test('another account gets its own key', () async {
    await attestor().attest(requestHash: 'h');
    account = 'account-2';
    final other = await attestor().attest(requestHash: 'h');
    expect((other as Attested).token, startsWith('appattest key-2 '));
    expect(server.registered, hasLength(2));
  });

  test('a key Apple no longer knows is forgotten', () async {
    await attestor().attest(requestHash: 'h');
    apple.assertionError = PlatformException(code: 'invalid_key');
    expect(
      await attestor().attest(requestHash: 'h'),
      isA<AttestationUnavailable>(),
    );
    apple.assertionError = null;
    final again = await attestor().attest(requestHash: 'h');
    expect((again as Attested).token, startsWith('appattest key-2 '));
  });

  test('no proof when unsupported, signed out or switched off', () async {
    apple.supported = false;
    expect(
      ((await attestor().attest(
        requestHash: 'h',
      )) as AttestationUnavailable).reason,
      AttestationUnavailableReason.unsupported,
    );
    apple.supported = true;
    account = null;
    expect(
      await attestor().attest(requestHash: 'h'),
      isA<AttestationUnavailable>(),
    );
    account = 'account-1';
    server.off = true;
    expect(
      ((await attestor().attest(
        requestHash: 'h',
      )) as AttestationUnavailable).reason,
      AttestationUnavailableReason.notConfigured,
    );
    expect(store.values, isEmpty);
  });

  test('the server client talks to the App Attest endpoints', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return switch (request.url.path) {
        '/v1/integrity/app-attest/challenges' => http.Response(
          jsonEncode({'challenge': 'Y2g='}),
          201,
        ),
        _ => http.Response('', 204),
      };
    });
    final api = HttpAppAttestServer(
      baseUrl: Uri.parse('https://vault.example.org/'),
      accessToken: () async => 'token',
      client: client,
    );

    expect(await api.challenge(), 'Y2g=');
    await api.registerKey(keyId: 'k', attestation: 'a', challenge: 'Y2g=');

    expect(requests.first.headers['Authorization'], 'Bearer token');
    expect(jsonDecode(requests.last.body), {
      'key_id': 'k',
      'attestation': 'a',
      'challenge': 'Y2g=',
    });

    final off = HttpAppAttestServer(
      baseUrl: Uri.parse('https://vault.example.org/'),
      accessToken: () async => 'token',
      client: MockClient((_) async => http.Response('', 404)),
    );
    expect(off.challenge, throwsA(isA<AppAttestOff>()));
  });
}
