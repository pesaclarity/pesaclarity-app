import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../features/security/data/secure_store.dart';
import 'integrity_attestor.dart';

/// Apple's App Attest on the iPhone (`AppAttestChannel.swift`).
abstract interface class AppAttestService {
  /// False on the simulator and on iPhones without the Secure Enclave.
  Future<bool> isSupported();

  /// A new key in the Secure Enclave; returns its key id, base64.
  Future<String> generateKey();

  /// Apple's attestation of [keyId] over [clientDataHash], base64.
  Future<String> attestKey(String keyId, List<int> clientDataHash);

  /// A signature by [keyId] over [clientDataHash], base64.
  Future<String> generateAssertion(String keyId, List<int> clientDataHash);
}

/// [AppAttestService] over the `com.pesaclarity.app/app_attest` channel.
class PlatformAppAttestService implements AppAttestService {
  const PlatformAppAttestService();

  static const _channel = MethodChannel('com.pesaclarity.app/app_attest');

  @override
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String> generateKey() async =>
      (await _channel.invokeMethod<String>('generateKey'))!;

  @override
  Future<String> attestKey(String keyId, List<int> clientDataHash) async =>
      (await _channel.invokeMethod<String>('attestKey', {
        'keyId': keyId,
        'clientDataHash': base64.encode(clientDataHash),
      }))!;

  @override
  Future<String> generateAssertion(
    String keyId,
    List<int> clientDataHash,
  ) async => (await _channel.invokeMethod<String>('generateAssertion', {
    'keyId': keyId,
    'clientDataHash': base64.encode(clientDataHash),
  }))!;
}

/// The server has App Attest switched off.
class AppAttestOff implements Exception {
  const AppAttestOff();
}

/// The server side of key registration (`/v1/integrity/app-attest`).
abstract interface class AppAttestServer {
  /// A one-time challenge, base64.
  Future<String> challenge();

  Future<void> registerKey({
    required String keyId,
    required String attestation,
    required String challenge,
  });
}

/// [AppAttestServer] on the vault server, signed in with [accessToken].
class HttpAppAttestServer implements AppAttestServer {
  HttpAppAttestServer({
    required this.baseUrl,
    required this.accessToken,
    required this.client,
  });

  final Uri baseUrl;
  final Future<String?> Function() accessToken;
  final http.Client client;

  Uri _path(String name) => baseUrl.resolve('v1/integrity/app-attest/$name');

  Future<Map<String, String>> _headers() async {
    final token = await accessToken();
    if (token == null) throw StateError('Not signed in');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  void _check(http.Response response) {
    if (response.statusCode == 404) throw const AppAttestOff();
    if (response.statusCode >= 300) {
      throw http.ClientException('App Attest: ${response.statusCode}');
    }
  }

  @override
  Future<String> challenge() async {
    final response = await client.post(
      _path('challenges'),
      headers: await _headers(),
    );
    _check(response);
    return (jsonDecode(response.body) as Map<String, Object?>)['challenge']!
        as String;
  }

  @override
  Future<void> registerKey({
    required String keyId,
    required String attestation,
    required String challenge,
  }) async {
    final response = await client.post(
      _path('keys'),
      headers: await _headers(),
      body: jsonEncode({
        'key_id': keyId,
        'attestation': attestation,
        'challenge': challenge,
      }),
    );
    _check(response);
  }
}

/// App Attest for the `appstore` flavour.
///
/// The first request registers a key for the signed-in account: the server
/// sends a challenge, Apple attests a new key over it, and the server keeps
/// the key. Each request after that carries the key's signature over its
/// request hash, as `appattest <key id> <assertion>`. The key id is kept per
/// account, so signing in to another account registers a new key.
class AppAttestAttestor implements IntegrityAttestor {
  AppAttestAttestor({
    required this.service,
    required this.server,
    required this.store,
    required this.accountId,
  });

  static const storeKey = 'app_attest_key';

  final AppAttestService service;
  final AppAttestServer server;
  final SecureStore store;

  /// The signed-in account, or null when nobody is.
  final Future<String?> Function() accountId;

  static List<int> _sha256(List<int> data) =>
      Sha256().toSync().hashSync(data).bytes;

  Future<String> _keyFor(String account) async {
    final saved = await store.read(storeKey);
    if (saved != null) {
      final row = jsonDecode(saved) as Map<String, Object?>;
      if (row['account'] == account) return row['keyId']! as String;
    }
    final keyId = await service.generateKey();
    final challenge = await server.challenge();
    final attestation = await service.attestKey(
      keyId,
      _sha256(base64.decode(challenge)),
    );
    await server.registerKey(
      keyId: keyId,
      attestation: attestation,
      challenge: challenge,
    );
    await store.write(
      storeKey,
      jsonEncode({'account': account, 'keyId': keyId}),
    );
    return keyId;
  }

  @override
  Future<Attestation> attest({required String requestHash}) async {
    if (!await service.isSupported()) {
      return const AttestationUnavailable(
        AttestationUnavailableReason.unsupported,
      );
    }
    final account = await accountId();
    if (account == null) {
      return const AttestationUnavailable(AttestationUnavailableReason.failed);
    }
    try {
      final keyId = await _keyFor(account);
      final assertion = await service.generateAssertion(
        keyId,
        _sha256(utf8.encode(requestHash)),
      );
      return Attested('appattest $keyId $assertion');
    } on AppAttestOff {
      return const AttestationUnavailable(
        AttestationUnavailableReason.notConfigured,
      );
    } on PlatformException catch (e) {
      // Apple no longer knows the key, such as after a restore to a new
      // iPhone: forget it so the next request registers a fresh one.
      if (e.code == 'invalid_key') await store.delete(storeKey);
      return const AttestationUnavailable(AttestationUnavailableReason.failed);
    } on Object {
      return const AttestationUnavailable(AttestationUnavailableReason.failed);
    }
  }
}
