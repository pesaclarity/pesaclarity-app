import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pesaclarity/src/config/build_info.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/features/app_status/application/app_status_providers.dart';
import 'package:pesaclarity/src/features/app_status/application/message_rereader.dart';
import 'package:pesaclarity/src/features/app_status/application/update_links.dart';
import 'package:pesaclarity/src/features/app_status/data/app_status_source.dart';

/// A placeholder key for tests only: a fixed seed, never a real one.
final testSeed = List<int>.filled(32, 7);

/// Another key, which the app does not pin.
final otherSeed = List<int>.filled(32, 9);

/// Tuesday 17 November 2026, 11:00 EAT.
final testNow = DateTime.utc(2026, 11, 17, 8);

Future<String> publicKeyOf(List<int> seed) async {
  final pair = await Ed25519().newKeyPairFromSeed(seed);
  return base64.encode((await pair.extractPublicKey()).bytes);
}

/// Signs [payload] as the server does.
Future<Map<String, Object?>> signed(
  Map<String, Object?> payload, {
  List<int>? seed,
}) async {
  final pair = await Ed25519().newKeyPairFromSeed(seed ?? testSeed);
  final data = utf8.encode(jsonEncode(payload));
  final signature = await Ed25519().sign([
    ...utf8.encode('pesaclarity.app-status.v1\n'),
    ...data,
  ], keyPair: pair);
  return {
    'alg': 'Ed25519',
    'payload': base64.encode(data),
    'signature': base64.encode(signature.bytes),
  };
}

Map<String, Object?> updateNotice({
  String id = 'n-040',
  String latest = '0.4.0',
  String? min,
  String? reason,
  String title = 'Pesa Clarity 0.4.0 is ready',
  String body = 'Reads Equity card payments and fixes Fuliza totals.',
}) => {
  'id': id,
  'kind': 'update',
  'title': title,
  'body': body,
  'latest_version': latest,
  'min_version': min,
  'required_reason': reason,
  'reread_from': null,
};

Map<String, Object?> infoNotice({String id = 'n-kcb', String? rereadFrom}) => {
  'id': id,
  'kind': 'info',
  'title': 'KCB changed its messages',
  'body':
      'Some KCB payments from 10 Nov were missed. We read them again: '
      '4 found.',
  'latest_version': null,
  'min_version': null,
  'required_reason': null,
  'reread_from': rereadFrom,
};

Map<String, Object?> payload({
  List<Map<String, Object?>> notices = const [],
  DateTime? issuedAt,
  String version = '0.3.0',
  String build = 'play',
  String platform = 'android',
  String? latest,
}) => {
  'format': 1,
  'issued_at': (issuedAt ?? testNow).toUtc().toIso8601String(),
  'version': version,
  'build': build,
  'platform': platform,
  'latest_version': latest,
  'notices': notices,
};

/// The server: answers with [response] (null as if offline) and counts asks.
class FakeAppStatusSource implements AppStatusSource {
  FakeAppStatusSource([this.response]);

  Object? response;
  final asked = <Map<String, String>>[];

  @override
  Future<Object?> fetch({
    required String version,
    required String build,
    required String platform,
  }) async {
    asked.add({'version': version, 'build': build, 'platform': platform});
    return response;
  }
}

class MemorySettings implements AppSettingsRepository {
  final values = <String, Map<String, Object?>>{};

  @override
  Future<Map<String, Object?>?> readJson(String key) async =>
      values[key] == null
      ? null
      : jsonDecode(jsonEncode(values[key])) as Map<String, Object?>;

  @override
  Future<void> writeJson(String key, Map<String, Object?> value) async {
    values[key] = jsonDecode(jsonEncode(value)) as Map<String, Object?>;
  }
}

class FakeRereader implements MessageRereader {
  FakeRereader({this.accepts = true});

  bool accepts;
  final asked = <DateTime>[];

  @override
  Future<bool> requestReread(DateTime from) async {
    asked.add(from);
    return accepts;
  }
}

class FakeUpdateOpener implements UpdateOpener {
  final opened = <Uri>[];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return true;
  }
}

List<Override> appStatusOverrides({
  required FakeAppStatusSource source,
  required String publicKey,
  required MemorySettings settings,
  DateTime Function()? clock,
  String version = '0.3.0',
  AppFlavor flavor = AppFlavor.play,
  MessageRereader? rereader,
  UpdateOpener? opener,
}) => [
  appStatusSourceProvider.overrideWithValue(source),
  appStatusPublicKeysProvider.overrideWithValue([publicKey]),
  mainSettingsRepositoryProvider.overrideWithValue(settings),
  buildVersionProvider.overrideWithValue(version),
  appFlavorProvider.overrideWithValue(flavor),
  clockProvider.overrideWithValue(clock ?? () => testNow),
  if (rereader != null) messageRereaderProvider.overrideWithValue(rereader),
  if (opener != null) updateOpenerProvider.overrideWithValue(opener),
];
