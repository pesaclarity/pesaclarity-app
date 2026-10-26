import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Supplies the 256-bit SQLCipher key for the on-phone database.
abstract interface class DatabaseKeyStore {
  /// Returns the key as 64 hex characters, creating and storing it on first use.
  Future<String> readOrCreateKey();
}

/// Keeps the database key in Android Keystore-backed secure storage.
///
/// TODO(security): release the key only after BiometricPrompt or PIN unlock,
/// and prefer StrongBox where available (spec: Mobile security).
class SecureStorageDatabaseKeyStore implements DatabaseKeyStore {
  SecureStorageDatabaseKeyStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _keyName = 'pesaclarity.db.key.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String> readOrCreateKey() async {
    final existing = await _storage.read(key: _keyName);
    if (existing != null) return existing;

    final key = generateDatabaseKey();
    await _storage.write(key: _keyName, value: key);
    return key;
  }
}

/// Generates a random 256-bit key as 64 lowercase hex characters.
String generateDatabaseKey([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(
    32,
    (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
