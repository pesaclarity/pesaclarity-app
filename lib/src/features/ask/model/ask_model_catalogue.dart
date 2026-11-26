import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The money models Ask can download.
enum AskModelTier { light, full }

/// The bundled, signed list of models (`tool/sign_ask_models.dart` writes it).
const askModelCatalogueAsset = 'assets/models/ask/ask-models.signed.json';

/// The Ed25519 public keys the catalogue must be signed with, as base64 of
/// the 32 raw bytes. Compiled in, never downloaded, like the app status keys:
/// changing them is a reviewed code change.
const askModelCataloguePublicKeys = <String>[
  'ON+Lpo2lC+iJYv1QYx28UrPbjntoHN8o8CRfXBZROy0=',
];

/// Comes before the payload in the signed bytes.
final _signingContext = utf8.encode('pesaclarity.ask-models.v1\n');

const _payloadFormat = 1;

/// Models are fetched only from this repository's GitHub releases.
const askModelUrlPrefix =
    'https://github.com/pesaclarity/pesaclarity-app/releases/download/';

/// One model in the catalogue.
class AskModelEntry {
  const AskModelEntry({
    required this.tier,
    required this.file,
    required this.url,
    required this.sizeBytes,
    required this.sha256,
    required this.minRamMb,
    required this.parameters,
    required this.licence,
    required this.credit,
  });

  final AskModelTier tier;

  /// The file name on the phone, such as `ask-light.weights`.
  final String file;

  /// A GitHub release asset under [askModelUrlPrefix].
  final String url;
  final int sizeBytes;

  /// Lowercase hex.
  final String sha256;

  /// The phone memory it needs, such as 3072 for 3 GB.
  final int minRamMb;

  /// Such as `135M`.
  final String parameters;

  /// Such as `Apache-2.0`.
  final String licence;

  /// Such as `SmolLM2, fine-tuned for Pesa Clarity`.
  final String credit;

  /// The size in whole megabytes, as the screens say it.
  int get sizeMb => (sizeBytes / 1000000).round();

  /// Reads one entry, or null when anything is missing or out of shape.
  static AskModelEntry? tryParse(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final tier = AskModelTier.values.asNameMap()[json['tier']];
    final file = json['file'];
    final url = json['url'];
    final size = json['size'];
    final sha = json['sha256'];
    final ram = json['min_ram_mb'];
    final params = json['parameters'];
    final licence = json['licence'];
    final credit = json['credit'];
    if (tier == null ||
        file is! String ||
        !RegExp(r'^[a-z0-9][a-z0-9._-]*\.weights$').hasMatch(file) ||
        url is! String ||
        !url.startsWith(askModelUrlPrefix) ||
        size is! int ||
        size <= 0 ||
        sha is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha) ||
        ram is! int ||
        ram <= 0 ||
        params is! String ||
        licence is! String ||
        credit is! String) {
      return null;
    }
    return AskModelEntry(
      tier: tier,
      file: file,
      url: url,
      sizeBytes: size,
      sha256: sha,
      minRamMb: ram,
      parameters: params,
      licence: licence,
      credit: credit,
    );
  }

  Map<String, Object?> toJson() => {
    'tier': tier.name,
    'file': file,
    'url': url,
    'size': sizeBytes,
    'sha256': sha256,
    'min_ram_mb': minRamMb,
    'parameters': parameters,
    'licence': licence,
    'credit': credit,
  };
}

/// The models, checked: signed by a pinned key and well formed.
class AskModelCatalogue {
  const AskModelCatalogue(this.models);

  static const empty = AskModelCatalogue([]);

  final List<AskModelEntry> models;

  AskModelEntry? operator [](AskModelTier tier) {
    for (final m in models) {
      if (m.tier == tier) return m;
    }
    return null;
  }

  /// The payload's JSON, as `tool/sign_ask_models.dart` signs it.
  static Map<String, Object?> payload(List<AskModelEntry> models) => {
    'format': _payloadFormat,
    'models': [for (final m in models) m.toJson()],
  };

  /// The bytes the signature covers.
  static Uint8List signedBytes(List<int> payload) =>
      Uint8List.fromList([..._signingContext, ...payload]);

  /// Reads [envelope] (`{"alg","payload","signature"}`) when a key in
  /// [publicKeys] signed it; [AskModelCatalogue.empty] otherwise, so no model
  /// is offered. Never throws.
  static Future<AskModelCatalogue> verify(
    Object? envelope, {
    List<String> publicKeys = askModelCataloguePublicKeys,
  }) async {
    if (envelope is! Map<String, Object?> || envelope['alg'] != 'Ed25519') {
      return empty;
    }
    final payload = _decode(envelope['payload']);
    final signature = _decode(envelope['signature']);
    if (payload == null || signature == null || signature.length != 64) {
      return empty;
    }
    final message = signedBytes(payload);
    var signed = false;
    for (final key in publicKeys) {
      final bytes = _decode(key);
      if (bytes == null || bytes.length != 32) continue;
      try {
        if (await Ed25519().verify(
          message,
          signature: Signature(
            signature,
            publicKey: SimplePublicKey(bytes, type: KeyPairType.ed25519),
          ),
        )) {
          signed = true;
          break;
        }
      } on Object {
        continue;
      }
    }
    if (!signed) return empty;
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(payload));
    } on FormatException {
      return empty;
    }
    if (json is! Map<String, Object?> || json['format'] != _payloadFormat) {
      return empty;
    }
    final list = json['models'];
    final models = <AskModelEntry>[];
    if (list is List) {
      for (final item in list) {
        final entry = AskModelEntry.tryParse(item);
        if (entry != null && models.every((m) => m.tier != entry.tier)) {
          models.add(entry);
        }
      }
    }
    models.sort((a, b) => a.tier.index.compareTo(b.tier.index));
    return AskModelCatalogue(models);
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
