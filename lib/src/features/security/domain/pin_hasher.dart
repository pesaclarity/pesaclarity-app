import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Number of digits in an app PIN.
const pinLength = 6;

/// Whether [pin] is a well-formed app PIN.
bool isValidPin(String pin) => RegExp('^[0-9]{$pinLength}\$').hasMatch(pin);

/// Argon2id cost for app PINs, stored with each PIN so it can be raised later.
final class PinKdfParams {
  const PinKdfParams({required this.memoryKiB, required this.iterations});

  /// OWASP's minimum Argon2id setting (19 MiB, t = 2, p = 1). Unlocking runs
  /// it on every open, so it stays below the backup KDF cost.
  static const recommended = PinKdfParams(memoryKiB: 19 * 1024, iterations: 2);

  final int memoryKiB;
  final int iterations;

  Map<String, Object> toJson() => {'m': memoryKiB, 't': iterations};

  static PinKdfParams fromJson(Map<String, Object?> json) =>
      PinKdfParams(memoryKiB: json['m']! as int, iterations: json['t']! as int);
}

/// The two halves derived from a PIN: a verifier to store and a key that
/// wraps the database key.
final class PinSecrets {
  const PinSecrets(this.verifier, this.wrappingKey);

  final Uint8List verifier;
  final Uint8List wrappingKey;
}

/// Derives [PinSecrets] from a PIN with salted Argon2id.
class PinHasher {
  /// With [useIsolate] the slow hash runs off the UI thread.
  const PinHasher({this.useIsolate = true});

  final bool useIsolate;

  Future<PinSecrets> derive(
    String pin,
    List<int> salt,
    PinKdfParams params,
  ) async {
    final bytes = useIsolate
        ? await Isolate.run(() => _derive(pin, salt, params))
        : await _derive(pin, salt, params);
    return PinSecrets(
      Uint8List.sublistView(bytes, 0, 32),
      Uint8List.sublistView(bytes, 32, 64),
    );
  }

  static Future<Uint8List> _derive(
    String pin,
    List<int> salt,
    PinKdfParams params,
  ) async {
    final key = await DartArgon2id(
      parallelism: 1,
      memory: params.memoryKiB,
      iterations: params.iterations,
      hashLength: 64,
    ).deriveKey(secretKey: SecretKey(utf8.encode(pin)), nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }
}

/// Compares two byte lists in time that depends only on their length.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
