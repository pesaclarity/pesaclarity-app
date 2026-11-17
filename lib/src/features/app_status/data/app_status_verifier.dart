import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/app_status.dart';
import '../domain/app_version.dart';

/// Comes before the payload in the signed bytes, as the server signs them.
final _signingContext = utf8.encode('pesaclarity.app-status.v1\n');

const _payloadFormat = 1;

/// Checks a signed app status response and reads it.
///
/// Anything it cannot check comes back as null: no signature, a key that is
/// not pinned, a payload made for another version, build or platform, one
/// issued too long ago or in the future, or one older than a response
/// already accepted, so an old notice cannot be replayed.
class AppStatusVerifier {
  AppStatusVerifier(
    List<String> publicKeys, {
    this.maxAge = const Duration(days: 2),
    this.maxSkew = const Duration(hours: 1),
  }) : _keys = [
         for (final key in publicKeys)
           if (_decode(key) case final bytes? when bytes.length == 32)
             SimplePublicKey(bytes, type: KeyPairType.ed25519),
       ];

  final List<SimplePublicKey> _keys;

  /// How old a response may be.
  final Duration maxAge;

  /// How far ahead of the phone's clock a response may be.
  final Duration maxSkew;

  final _ed25519 = Ed25519();

  /// Whether any pinned key is usable. Without one nothing can be verified.
  bool get hasKeys => _keys.isNotEmpty;

  Future<AppStatus?> verify(
    Object? envelope, {
    required String version,
    required String build,
    required String platform,
    required DateTime now,
    DateTime? notBefore,
  }) async {
    if (envelope is! Map<String, Object?> || envelope['alg'] != 'Ed25519') {
      return null;
    }
    final payload = _decode(envelope['payload']);
    final signature = _decode(envelope['signature']);
    if (payload == null || signature == null || signature.length != 64) {
      return null;
    }
    if (!await _signedByPinnedKey(payload, signature)) return null;

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(payload));
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final current = AppVersion.tryParse(version);
    final issuedAt = switch (json['issued_at']) {
      final String text => DateTime.tryParse(text)?.toUtc(),
      _ => null,
    };
    if (current == null ||
        issuedAt == null ||
        json['format'] != _payloadFormat ||
        json['version'] != version ||
        json['build'] != build ||
        json['platform'] != platform) {
      return null;
    }
    final utcNow = now.toUtc();
    if (issuedAt.isAfter(utcNow.add(maxSkew)) ||
        utcNow.difference(issuedAt) > maxAge ||
        (notBefore != null && issuedAt.isBefore(notBefore))) {
      return null;
    }
    final notices = json['notices'];
    final latest = json['latest_version'];
    return AppStatus(
      issuedAt: issuedAt,
      current: current,
      latestVersion: latest is String ? AppVersion.tryParse(latest) : null,
      notices: [
        if (notices is List)
          for (final item in notices) ?AppNotice.fromJson(item),
      ],
    );
  }

  Future<bool> _signedByPinnedKey(
    Uint8List payload,
    Uint8List signature,
  ) async {
    final message = Uint8List.fromList([..._signingContext, ...payload]);
    for (final key in _keys) {
      try {
        if (await _ed25519.verify(
          message,
          signature: Signature(signature, publicKey: key),
        )) {
          return true;
        }
      } on Object {
        continue;
      }
    }
    return false;
  }

  static Uint8List? _decode(Object? value) {
    if (value is! String || value.isEmpty) return null;
    try {
      return base64.decode(value);
    } on FormatException {
      return null;
    }
  }
}
