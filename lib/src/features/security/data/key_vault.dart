import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import '../../../data/database/database_key_store.dart';
import '../domain/lock_settings.dart';
import '../domain/pin_hasher.dart';
import 'secure_store.dart';

/// Wrong PIN tries so far and when the next try is allowed.
final class PinAttempts {
  const PinAttempts({this.failed = 0, this.retryAt});

  final int failed;
  final DateTime? retryAt;
}

/// Holds the database key and decides when it is released.
///
/// Without an app PIN the key sits in Keystore-backed storage, as it did
/// before app lock existed. Once a PIN is set the stored copy is replaced by
/// one encrypted with a key derived from the PIN (Argon2id, then AES-GCM), so
/// the database cannot be opened until the PIN is entered. Turning on
/// fingerprint unlock keeps a second copy that is read only after the
/// biometric prompt succeeds.
class KeyVault {
  KeyVault(
    this._store, {
    this.hasher = const PinHasher(),
    this.kdfParams = PinKdfParams.recommended,
    Random? random,
  }) : _random = random ?? Random.secure();

  static const plainKeyName = 'pesaclarity.db.key.v1';
  static const pinRecordName = 'pesaclarity.lock.pin.v1';
  static const biometricKeyName = 'pesaclarity.db.key.bio.v1';
  static const settingsName = 'pesaclarity.lock.settings.v1';
  static const attemptsName = 'pesaclarity.lock.attempts.v1';

  final SecureStore _store;
  final PinHasher hasher;

  /// Cost for newly set PINs; existing PINs keep the cost they were set with.
  final PinKdfParams kdfParams;
  final Random _random;
  final _aes = DartAesGcm.with256bits();

  /// Reads the saved settings and tidies up after an interrupted change.
  Future<LockSettings> readSettings() async {
    final pinSet = await _store.read(pinRecordName) != null;
    if (pinSet) {
      // A PIN was set but the app stopped before the open copy was removed.
      await _store.delete(plainKeyName);
    } else {
      await _store.delete(biometricKeyName);
    }
    final raw = await _store.read(settingsName);
    final json = raw == null
        ? const <String, Object?>{}
        : jsonDecode(raw) as Map<String, Object?>;
    return LockSettings.fromJson(json, pinSet: pinSet);
  }

  Future<void> writeSettings(LockSettings settings) =>
      _store.write(settingsName, jsonEncode(settings.toJson()));

  /// The key when no PIN is set, created on first use.
  Future<String> readOrCreateOpenKey() async {
    if (await _store.read(pinRecordName) != null) {
      throw StateError('App lock is on; unlock with the PIN first');
    }
    final existing = await _store.read(plainKeyName);
    if (existing != null) return existing;
    final key = generateDatabaseKey(_random);
    await _store.write(plainKeyName, key);
    return key;
  }

  /// The key if [pin] is right, otherwise null.
  Future<String?> unlockWithPin(String pin) async {
    final raw = await _store.read(pinRecordName);
    if (raw == null) return null;
    final record = jsonDecode(raw) as Map<String, Object?>;
    final secrets = await hasher.derive(
      pin,
      base64Decode(record['salt']! as String),
      PinKdfParams.fromJson(record['kdf']! as Map<String, Object?>),
    );
    final verifier = base64Decode(record['verifier']! as String);
    if (!constantTimeEquals(secrets.verifier, verifier)) return null;

    final box = SecretBox(
      base64Decode(record['wrapped']! as String),
      nonce: base64Decode(record['nonce']! as String),
      mac: Mac(base64Decode(record['mac']! as String)),
    );
    final keyBytes = await _aes.decrypt(
      box,
      secretKey: SecretKeyData(secrets.wrappingKey),
    );
    return _hex(keyBytes);
  }

  /// The biometric copy of the key. Call only after the prompt succeeds.
  Future<String?> readBiometricKey() => _store.read(biometricKeyName);

  /// Sets or changes the PIN, wrapping [databaseKey] under it, and removes
  /// the open copy of the key.
  Future<void> setPin(String pin, String databaseKey) async {
    if (!isValidPin(pin)) throw ArgumentError('PIN must be $pinLength digits');
    final salt = _randomBytes(16);
    final secrets = await hasher.derive(pin, salt, kdfParams);
    final box = await _aes.encrypt(
      _unhex(databaseKey),
      secretKey: SecretKeyData(secrets.wrappingKey),
      nonce: _randomBytes(12),
    );
    await _store.write(
      pinRecordName,
      jsonEncode({
        'v': 1,
        'kdf': kdfParams.toJson(),
        'salt': base64Encode(salt),
        'verifier': base64Encode(secrets.verifier),
        'nonce': base64Encode(box.nonce),
        'wrapped': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    );
    await _store.delete(plainKeyName);
    await clearAttempts();
  }

  /// Turns the lock off: the key goes back to Keystore-backed storage.
  Future<void> removePin(String databaseKey) async {
    await _store.write(plainKeyName, databaseKey);
    await _store.delete(biometricKeyName);
    await _store.delete(pinRecordName);
    await clearAttempts();
  }

  Future<void> enableBiometric(String databaseKey) =>
      _store.write(biometricKeyName, databaseKey);

  Future<void> disableBiometric() => _store.delete(biometricKeyName);

  Future<PinAttempts> readAttempts() async {
    final raw = await _store.read(attemptsName);
    if (raw == null) return const PinAttempts();
    final json = jsonDecode(raw) as Map<String, Object?>;
    final retryAt = json['retryAt'] as String?;
    return PinAttempts(
      failed: json['failed'] as int? ?? 0,
      retryAt: retryAt == null ? null : DateTime.parse(retryAt),
    );
  }

  Future<void> writeAttempts(PinAttempts attempts) => _store.write(
    attemptsName,
    jsonEncode({
      'failed': attempts.failed,
      'retryAt': attempts.retryAt?.toUtc().toIso8601String(),
    }),
  );

  Future<void> clearAttempts() => _store.delete(attemptsName);

  Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

List<int> _unhex(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];
